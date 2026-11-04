import Foundation
import Observation

/// Why the panel is closing, which decides where keyboard focus goes next.
enum PanelDismissal {
    /// An app is launching and takes focus itself.
    case launching
    /// Nothing launched, so focus goes back to the app the panel opened over.
    case cancelled
}

/// Source of truth for the search session: the loaded apps, the live query and
/// selection, transient UX flags, and the launch / dismiss callbacks the
/// owning controller wires up. `@Observable` so the SwiftUI view re-renders
/// when any of its stored properties change.
@Observable
final class LauncherModel {
    var apps: [AppRecord] = []
    var query: String = "" {
        // A new query is a new list, so start again from its top result.
        didSet { if query != oldValue { selection = nil } }
    }
    /// The row the user moved to. Held by identity rather than position, so a
    /// rescan can't slide it onto another app. `nil` means the top result.
    var selection: AppRecord.ID?

    var welcomeActive: Bool = true
    /// The hotkey in effect. `nil` until `HotkeyController` first evaluates it.
    var hotkeyBinding: HotkeyBinding?

    @ObservationIgnored var onLaunch: ((AppRecord, String) -> Void)?
    @ObservationIgnored var onDismissRequested: ((PanelDismissal) -> Void)?

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
            // Score the display name and the on-disk bundle name, keep the
            // best: "vscode" matches the file name "Visual Studio Code" even
            // though the display name is just "Code".
            let candidates = app.fileName == app.displayName
                ? [Matcher.score(query: query, target: app.displayName)]
                : [Matcher.score(query: query, target: app.displayName),
                   Matcher.score(query: query, target: app.fileName)]
            guard let s = candidates.compactMap({ $0 }).max() else { continue }
            let mult = frecency.multiplier(query: query, bundleId: app.bundleId)
            // Gap penalties can drive the match score negative; multiplying a
            // negative base by a frecency boost (> 1) would rank the app
            // *worse* the more it's launched. Floor at 1 so frecency only helps.
            scored.append((app, max(Double(s), 1) * mult))
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

    /// The app Return would launch: the chosen row if it's still listed,
    /// otherwise the top result.
    func selectedApp(in results: [AppRecord]) -> AppRecord? {
        results.first { $0.id == selection } ?? results.first
    }

    func reset() {
        query = ""
        selection = nil
    }

    func selectNext() {
        moveSelection(by: 1)
    }

    func selectPrev() {
        moveSelection(by: -1)
    }

    private func moveSelection(by offset: Int) {
        let r = results
        guard !r.isEmpty else { return }
        let current = r.firstIndex { $0.id == selection } ?? 0
        selection = r[min(max(current + offset, 0), r.count - 1)].id
    }

    func launchSelection() {
        guard let app = selectedApp(in: results) else {
            onDismissRequested?(.cancelled)
            return
        }
        onLaunch?(app, query)
        onDismissRequested?(.launching)
    }
}
