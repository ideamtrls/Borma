import Foundation

/// Persists whether the user has dismissed the launcher panel at least once.
/// Used to gate the one-time hotkey-hint footer beneath the search field.
struct WelcomeFlag {
    private static let dismissedKey = "borma.welcome.dismissed"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isActive: Bool { !defaults.bool(forKey: Self.dismissedKey) }

    func retire() { defaults.set(true, forKey: Self.dismissedKey) }
}
