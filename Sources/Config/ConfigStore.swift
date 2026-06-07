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
        } catch {
            Log.config.error("Failed to load config at \(self.fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
