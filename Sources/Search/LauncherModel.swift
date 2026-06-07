import Foundation
import KeyboardShortcuts
import Observation

/// Source of truth for the search session: the loaded apps, the live query and
/// selection, transient UX flags, and the launch / dismiss callbacks the
/// owning controller wires up. `@Observable` so the SwiftUI view re-renders
/// when any of its stored properties change.
@Observable
final class LauncherModel {
    var apps: [AppRecord] = []
    var query: String = ""
    var selection: Int = 0

    var welcomeActive: Bool = true
    var conflictActive: Bool = false
    var activeHotkey: KeyboardShortcuts.Shortcut?

    @ObservationIgnored var onLaunch: ((AppRecord, String) -> Void)?
    @ObservationIgnored var onDismissRequested: (() -> Void)?

    private let frecency: FrecencyStore

    init(frecency: FrecencyStore) {
        self.frecency = frecency
    }

    /// Maximum number of results shown in the panel.
    static let maxResults = 8

    var results: [AppRecord] {
        guard !query.isEmpty else { return [] }
        var scored: [(AppRecord, Double)] = []
        scored.reserveCapacity(apps.count)
        for app in apps {
            guard let s = Matcher.score(query: query, target: app.displayName) else { continue }
            let mult = frecency.multiplier(query: query, bundleId: app.bundleId)
            scored.append((app, Double(s) * mult))
        }
        scored.sort { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            if a.0.displayName.count != b.0.displayName.count {
                return a.0.displayName.count < b.0.displayName.count
            }
            return a.0.displayName.localizedCaseInsensitiveCompare(b.0.displayName) == .orderedAscending
        }
        return Array(scored.prefix(Self.maxResults)).map { $0.0 }
    }

    func reset() {
        query = ""
        selection = 0
    }

    func selectNext() {
        let count = results.count
        guard count > 0 else { return }
        selection = min(selection + 1, count - 1)
    }

    func selectPrev() {
        guard !results.isEmpty else { return }
        selection = max(selection - 1, 0)
    }

    func launchSelection() {
        let r = results
        guard r.indices.contains(selection) else {
            onDismissRequested?()
            return
        }
        onLaunch?(r[selection], query)
        onDismissRequested?()
    }
}
