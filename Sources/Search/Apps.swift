import AppKit

/// A discovered `.app` bundle eligible for launching.
///
/// `@unchecked Sendable` because `NSImage` is not formally `Sendable`. The
/// record is assembled on the main actor (where `NSWorkspace.icon(forFile:)`
/// loads the image) and is immutable thereafter, so passing it back to the
/// background scan is safe.
struct AppRecord: Identifiable, @unchecked Sendable {
    let bundleURL: URL
    let displayName: String
    /// The `.app` bundle's file name without extension. Often differs from
    /// `displayName` (e.g. "Visual Studio Code" vs. "Code") and is scored as
    /// an alternate match target.
    let fileName: String
    let bundleId: String
    let icon: NSImage

    var id: String { bundleId.isEmpty ? bundleURL.path : bundleId }
}

enum AppLauncher {
    static func launch(_ app: AppRecord) {
        NSWorkspace.shared.openApplication(
            at: app.bundleURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            guard let error else { return }
            Task { @MainActor in
                Log.app.error("Failed to launch \(app.bundleURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                NSSound.beep()
            }
        }
    }
}

enum AppScanner {
    static func scan(paths: [URL]) async -> [AppRecord] {
        await Task.detached(priority: .userInitiated) {
            await scanAsync(paths: paths)
        }.value
    }

    nonisolated private static func scanAsync(paths: [URL]) async -> [AppRecord] {
        let fm = FileManager.default
        var seenPaths = Set<String>()
        var seenBundleIds = Set<String>()
        var results: [AppRecord] = []

        for root in paths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            // FileManager's URL enumerator does not follow symlinks, so apps like
            // /Applications/Safari.app (a symlink into the system cryptex) are
            // invisible to it. Catch top-level .app entries with a flat pass.
            // Do not pass .skipsHiddenFiles here: the Safari symlink carries the
            // hidden flag and would be filtered out.
            var candidates: [URL] = []
            if let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                candidates.append(contentsOf: entries.filter {
                    $0.pathExtension == "app" && !$0.lastPathComponent.hasPrefix(".")
                })
            }
            if let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                // `.allObjects` eagerly drains the enumerator into an array.
                // Iterating the enumerator directly is unavailable in async
                // contexts because its `makeIterator` is marked unavailable.
                for case let url as URL in enumerator.allObjects where url.pathExtension == "app" {
                    candidates.append(url)
                }
            }

            for url in candidates {
                let path = url.standardizedFileURL.path
                guard seenPaths.insert(path).inserted else { continue }
                guard let record = await makeRecord(bundleURL: url) else { continue }
                if !record.bundleId.isEmpty, !seenBundleIds.insert(record.bundleId).inserted {
                    continue
                }
                results.append(record)
            }
        }
        return results
    }

    nonisolated private static func makeRecord(bundleURL: URL) async -> AppRecord? {
        let info = NSDictionary(
            contentsOf: bundleURL.appendingPathComponent("Contents/Info.plist")
        ) as? [String: Any] ?? [:]

        let bundleId = (info["CFBundleIdentifier"] as? String) ?? ""
        let displayName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent

        let resolvedPath = bundleURL.resolvingSymlinksInPath().path
        return await MainActor.run {
            let icon = NSWorkspace.shared.icon(forFile: resolvedPath)
            icon.size = NSSize(
                width: LauncherDimensions.resultIconSize,
                height: LauncherDimensions.resultIconSize
            )
            return AppRecord(
                bundleURL: bundleURL,
                displayName: displayName,
                fileName: bundleURL.deletingPathExtension().lastPathComponent,
                bundleId: bundleId,
                icon: icon
            )
        }
    }
}
