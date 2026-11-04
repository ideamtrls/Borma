import Foundation
import Observation
import SwiftUI

/// Loads, persists, and exposes the user-editable JSON config. Observable so
/// the settings UI binds directly to `config.*`; the owning controller hooks
/// `onChange` to call `save()` after edits.
@Observable
final class ConfigStore {
    @ObservationIgnored let fileURL: URL
    var config: Config = .default

    var searchPaths: [String] { config.searchPaths }
    var highlightColor: Color { config.highlightColor?.color ?? .accentColor }

    /// Every way reading the file can turn out.
    private enum ReadResult {
        case missing
        case loaded(Config)
        case malformed(DecodingError)
        case unreadable(any Error)
    }

    /// How long a live reload waits before reading a malformed file again.
    private static let partialWriteGrace: Duration = .milliseconds(500)

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Loads at startup, acting on the file as it is right now.
    func load() {
        apply(read())
    }

    /// Reloads after a file event. A malformed read may just be an editor's
    /// half-finished save, so it's read again before being treated as broken.
    func reload() async {
        var result = read()
        if case .malformed = result {
            try? await Task.sleep(for: Self.partialWriteGrace)
            result = read()
        }
        apply(result)
    }

    private func read() -> ReadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        do {
            let data = try Data(contentsOf: fileURL)
            return .loaded(try JSONDecoder().decode(Config.self, from: data))
        } catch let error as DecodingError {
            return .malformed(error)
        } catch {
            return .unreadable(error)
        }
    }

    private func apply(_ result: ReadResult) {
        switch result {
        case .missing:
            save()
        case .loaded(let loaded):
            config = loaded
        case .malformed(let error):
            // The file is user-editable, so this usually means a bad hand edit.
            // Move it aside so those edits can be recovered, then replace it
            // with the config in memory: defaults at startup, the last good
            // values after that. If it can't be moved, leave it alone.
            Log.config.error("Failed to decode config at \(self.fileURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
            do {
                try preserveBrokenFile()
                save()
            } catch {
                Log.config.error("Leaving broken config in place, failed to move it aside: \(error.localizedDescription, privacy: .public)")
            }
        case .unreadable(let error):
            Log.config.error("Failed to read config at \(self.fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Renames the unreadable config to `config.json.errors`, replacing any
    /// previous one.
    private func preserveBrokenFile() throws {
        let backupURL = fileURL.appendingPathExtension("errors")
        let fm = FileManager.default
        try? fm.removeItem(at: backupURL)
        try fm.moveItem(at: fileURL, to: backupURL)
        Log.config.notice("Moved broken config to \(backupURL.path, privacy: .public)")
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(config)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.config.error("Failed to save config to \(self.fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
