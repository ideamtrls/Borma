import AppKit
import Carbon.HIToolbox
import Foundation
import KeyboardShortcuts

/// ⌘⇧Space — both the out-of-box default for `.toggleBorma` and the binding
/// Borma falls back to when Spotlight still owns ⌘Space. Defined once so the
/// default and the fallback can't drift apart.
private let fallbackShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.command, .shift])

private let systemSettingsBundleID = "com.apple.systempreferences"

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
    private var settingsWatch: Task<Void, Never>?

    init(
        onTrigger: @escaping () -> Void,
        onBindingChanged: @escaping (Bool, KeyboardShortcuts.Shortcut?) -> Void
    ) {
        self.onBindingChanged = onBindingChanged

        KeyboardShortcuts.onKeyDown(for: .toggleBormaFallback, action: onTrigger)
        KeyboardShortcuts.onKeyDown(for: .toggleBorma, action: onTrigger)

        evaluateBinding()
        observeFrontmostApp()
    }

    func evaluateBinding() {
        let saved = KeyboardShortcuts.getShortcut(for: .toggleBorma)

        if conflictExists {
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

    private var savedIsCmdSpace: Bool {
        let saved = KeyboardShortcuts.getShortcut(for: .toggleBorma)
        return saved?.key == .space && saved?.modifiers == [.command]
    }

    private var conflictExists: Bool {
        savedIsCmdSpace && SpotlightConflict.isSpotlightOnCmdSpace()
    }

    /// macOS announces no change to its symbolic hotkeys, so the conflict is
    /// re-checked on every app switch. Summoning Borma counts as a switch.
    private func observeFrontmostApp() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            Task { @MainActor [weak self] in
                self?.frontmostAppDidChange(to: bundleID)
            }
        }
    }

    /// While System Settings is frontmost no app switch will follow the user
    /// changing the shortcut there, so check once a second until they leave.
    /// Without this, ⌘Space pressed right after freeing it in System Settings
    /// would do nothing.
    private func frontmostAppDidChange(to bundleID: String?) {
        settingsWatch?.cancel()
        settingsWatch = nil
        recheckConflict()

        guard bundleID == systemSettingsBundleID, savedIsCmdSpace else { return }
        settingsWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.recheckConflict()
            }
        }
    }

    /// Re-registers only when the answer changed. `evaluateBinding()` briefly
    /// unregisters hot keys, so it mustn't run on every check.
    private func recheckConflict() {
        guard conflictExists != isOnFallback else { return }
        Log.hotkey.notice("⌘Space conflict changed; on fallback: \(!self.isOnFallback, privacy: .public)")
        evaluateBinding()
    }
}

/// Asks Carbon whether an enabled system hotkey holds ⌘Space. Entries carry no
/// id, so this can't confirm the hotkey is Spotlight's; the default holder of
/// ⌘Space is Spotlight, and the fallback is right whichever one it is. Returns
/// `false` on failure, so Borma's binding proceeds.
private enum SpotlightConflict {
    static func isSpotlightOnCmdSpace() -> Bool {
        var hotkeys: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&hotkeys)
        guard status == noErr, let entries = hotkeys?.takeRetainedValue() as? [[String: Any]] else {
            Log.hotkey.error("CopySymbolicHotKeys failed: \(status, privacy: .public)")
            return false
        }

        return entries.contains { entry in
            (entry[kHISymbolicHotKeyEnabled] as? Bool) == true
                && (entry[kHISymbolicHotKeyCode] as? Int) == kVK_Space
                && (entry[kHISymbolicHotKeyModifiers] as? Int) == cmdKey
        }
    }
}
