import Foundation

struct FrecencyEntry: Codable {
    var launchCount: Int
    var lastLaunchedAt: TimeInterval
}

/// On-disk shape: `entries[bundleId][query] = FrecencyEntry`. The nested
/// dictionary keeps per-bundle prefix lookups O(queries-per-bundle) instead
/// of forcing a scan over every entry.
struct FrecencyData: Codable {
    static let currentVersion = 2

    var version: Int = currentVersion
    var entries: [String: [String: FrecencyEntry]] = [:]
}

/// Per-query launch history. Contributes a recency-weighted, frequency-aware
/// multiplier to the match score so repeatedly-launched apps surface faster.
final class FrecencyStore {
    let fileURL: URL
    private var data = FrecencyData()

    /// Recency decay: a launch contributes half of its weight after this much
    /// wall-clock time. Two weeks roughly matches Spotlight/Alfred behavior.
    private static let halfLife: TimeInterval = 14 * 24 * 60 * 60

    /// Damping applied when matching against a *prefix* of a previously-used
    /// query (e.g. the stored query was "saf" but the user typed "s"). Keeps
    /// long historical queries from over-dominating short typed prefixes.
    private static let prefixMatchDamping: Double = 0.7

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let raw = try? Data(contentsOf: fileURL) else {
            Log.frecency.error("Failed to read frecency at \(self.fileURL.path, privacy: .public)")
            return
        }
        let decoder = JSONDecoder()
        if let current = try? decoder.decode(FrecencyData.self, from: raw),
           current.version == FrecencyData.currentVersion {
            data = current
            return
        }
        if let v1 = try? decoder.decode(FrecencyDataV1.self, from: raw), v1.version == 1 {
            Log.frecency.notice("Migrating frecency v1 → v\(FrecencyData.currentVersion)")
            data = v1.migrated()
            save()
            return
        }
        Log.frecency.error("Unable to decode frecency, starting fresh")
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let raw = try encoder.encode(data)
            try raw.write(to: fileURL, options: .atomic)
        } catch {
            Log.frecency.error("Failed to write frecency: \(error.localizedDescription, privacy: .public)")
        }
    }

    func record(query: String, bundleId: String) {
        guard !bundleId.isEmpty else { return }
        let q = query.lowercased()
        var byQuery = data.entries[bundleId] ?? [:]
        var entry = byQuery[q] ?? FrecencyEntry(launchCount: 0, lastLaunchedAt: 0)
        entry.launchCount += 1
        entry.lastLaunchedAt = Date().timeIntervalSince1970
        byQuery[q] = entry
        data.entries[bundleId] = byQuery
        save()
    }

    func multiplier(query: String, bundleId: String) -> Double {
        guard !bundleId.isEmpty, let byQuery = data.entries[bundleId] else { return 1.0 }
        let q = query.lowercased()
        let now = Date().timeIntervalSince1970

        var best = 1.0
        if let exact = byQuery[q] {
            best = max(best, score(for: exact, now: now))
        }
        if !q.isEmpty {
            for (storedQuery, entry) in byQuery where storedQuery != q && storedQuery.hasPrefix(q) {
                best = max(best, score(for: entry, now: now) * Self.prefixMatchDamping)
            }
        }
        return best
    }

    private func score(for entry: FrecencyEntry, now: TimeInterval) -> Double {
        let age = max(0, now - entry.lastLaunchedAt)
        let recency = pow(0.5, age / Self.halfLife)
        let frequency = log(Double(entry.launchCount) + 1) + 1.0
        return 1.0 + frequency * recency
    }
}

/// Legacy on-disk shape: flat `[String: FrecencyEntry]` keyed by
/// `"<query>\u{1}<bundleId>"`. Kept only so installs from before the v2
/// migration don't lose their history on first launch.
private struct FrecencyDataV1: Codable {
    var version: Int
    var entries: [String: FrecencyEntry]

    func migrated() -> FrecencyData {
        var byBundle: [String: [String: FrecencyEntry]] = [:]
        for (key, entry) in entries {
            let parts = key.split(separator: "\u{1}", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            byBundle[parts[1], default: [:]][parts[0]] = entry
        }
        return FrecencyData(version: FrecencyData.currentVersion, entries: byBundle)
    }
}
