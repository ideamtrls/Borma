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

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            save()
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            config = try JSONDecoder().decode(Config.self, from: data)
        } catch let error as DecodingError {
            // The file is user-editable, so a decode failure usually means a
            // bad hand edit. Falling back to defaults in memory would let the
            // next save() silently overwrite those edits — move the file
            // aside first so they can be recovered.
            Log.config.error("Failed to decode config at \(self.fileURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
            preserveBrokenFile()
            config = .default
            save()
        } catch {
            Log.config.error("Failed to read config at \(self.fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Renames the unreadable config to `config.json.errors` (replacing any
    /// previous one) so a fresh default can be written in its place.
    private func preserveBrokenFile() {
        let backupURL = fileURL.appendingPathExtension("errors")
        let fm = FileManager.default
        do {
            try? fm.removeItem(at: backupURL)
            try fm.moveItem(at: fileURL, to: backupURL)
            Log.config.notice("Moved broken config to \(backupURL.path, privacy: .public)")
        } catch {
            Log.config.error("Failed to move broken config aside: \(error.localizedDescription, privacy: .public)")
        }
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
