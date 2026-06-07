import AppKit
import Foundation
import KeyboardShortcuts

/// ⌘⇧Space — both the out-of-box default for `.toggleBorma` and the binding
/// Borma falls back to when Spotlight still owns ⌘Space. Defined once so the
/// default and the fallback can't drift apart.
private let fallbackShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.command, .shift])

extension KeyboardShortcuts.Name {
    static let toggleBorma = Self("toggleBorma", default: fallbackShortcut)
    static let toggleBormaFallback = Self("toggleBormaFallback")
}

/// Owns the global hotkey wiring. Exposes whichever shortcut is currently
/// *active* in `activeShortcut` — this may differ from the user's saved
/// preference when Spotlight still owns ⌘Space.
///
/// Call `evaluateBinding()` whenever the user changes the shortcut in the
/// settings recorder; the `Recorder`'s `onChange:` callback is the wiring
/// point.
final class HotkeyController {
    private(set) var activeShortcut: KeyboardShortcuts.Shortcut?
    private(set) var isOnFallback: Bool = false

    private let onBindingChanged: (Bool, KeyboardShortcuts.Shortcut?) -> Void

    init(
        onTrigger: @escaping () -> Void,
        onBindingChanged: @escaping (Bool, KeyboardShortcuts.Shortcut?) -> Void
    ) {
        self.onBindingChanged = onBindingChanged

        KeyboardShortcuts.onKeyDown(for: .toggleBormaFallback, action: onTrigger)
        KeyboardShortcuts.onKeyDown(for: .toggleBorma, action: onTrigger)

        evaluateBinding()
    }

    func evaluateBinding() {
        let saved = KeyboardShortcuts.getShortcut(for: .toggleBorma)
        let savedIsCmdSpace = saved?.key == .space && saved?.modifiers == [.command]
        let conflict = savedIsCmdSpace && SpotlightConflict.isSpotlightOnCmdSpace()

        if conflict {
            KeyboardShortcuts.disable(.toggleBorma)
            KeyboardShortcuts.setShortcut(fallbackShortcut, for: .toggleBormaFallback)
            KeyboardShortcuts.enable(.toggleBormaFallback)
            activeShortcut = fallbackShortcut
            isOnFallback = true
        } else {
            KeyboardShortcuts.disable(.toggleBormaFallback)
            KeyboardShortcuts.setShortcut(nil, for: .toggleBormaFallback)
            KeyboardShortcuts.enable(.toggleBorma)
            activeShortcut = saved
            isOnFallback = false
        }

        onBindingChanged(isOnFallback, activeShortcut)
    }
}

/// Reads the system's symbolic hotkeys preference file to determine whether
/// Spotlight is currently bound to ⌘Space. Returns `false` on any read/decode
/// failure — i.e. we let Borma's binding proceed and rely on the user noticing.
private enum SpotlightConflict {
    static func isSpotlightOnCmdSpace() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.symbolichotkeys.plist")

        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization
                .propertyList(from: data, options: [], format: nil),
              let top = plist as? [String: Any],
              let map = top["AppleSymbolicHotKeys"] as? [String: Any],
              let entry = map["64"] as? [String: Any],
              (entry["enabled"] as? Bool) == true,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Int],
              parameters.count >= 3
        else { return false }

        let spaceKeyCode = 49
        let commandMask = 1_048_576
        return parameters[1] == spaceKeyCode && parameters[2] == commandMask
    }
}
