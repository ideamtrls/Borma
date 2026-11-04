import AppKit
import Carbon.HIToolbox
import Foundation
import KeyboardShortcuts

/// ⌘⇧Space — both the out-of-box default for `.toggleBorma` and the binding
/// Borma falls back to when Spotlight still owns ⌘Space. Defined once so the
/// default and the fallback can't drift apart.
private let fallbackShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.command, .shift])

private let cmdSpaceShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.command])

private let systemSettingsBundleID = "com.apple.systempreferences"

extension KeyboardShortcuts.Name {
    static let toggleBorma = Self("toggleBorma", default: fallbackShortcut)
    static let toggleBormaFallback = Self("toggleBormaFallback")
}

/// What opens Borma right now, which can differ from the user's saved shortcut.
enum HotkeyBinding: Equatable {
    /// The user cleared the recorder, so nothing is registered.
    case unbound
    /// The user's saved shortcut is live.
    case saved(KeyboardShortcuts.Shortcut)
    /// A system hotkey holds ⌘Space, so `fallbackShortcut` stands in for the
    /// saved ⌘Space.
    case fallback

    var shortcut: KeyboardShortcuts.Shortcut? {
        switch self {
        case .unbound: nil
        case .saved(let shortcut): shortcut
        case .fallback: fallbackShortcut
        }
    }

    /// `cmdSpaceTaken` is an autoclosure so that a shortcut other than ⌘Space
    /// never asks Carbon.
    static func resolve(
        saved: KeyboardShortcuts.Shortcut?,
        cmdSpaceTaken: @autoclosure () -> Bool
    ) -> Self {
        guard let saved else { return .unbound }
        return saved == cmdSpaceShortcut && cmdSpaceTaken() ? .fallback : .saved(saved)
    }

    /// Whether arriving here from `previous` means the usual hotkey has only
    /// now stopped working.
    func isNewConflict(since previous: Self?) -> Bool {
        self == .fallback && previous != .fallback
    }
}

/// Owns the global hotkey wiring.
///
/// Call `evaluateBinding()` whenever the user changes the shortcut in the
/// settings recorder; the `Recorder`'s `onChange:` callback is the wiring
/// point.
final class HotkeyController {
    /// The binding in effect. It starts from how the last run ended:
    /// `.toggleBormaFallback` only has a stored shortcut while on the fallback,
    /// so a conflict carried over from that run doesn't count as new.
    private(set) var binding: HotkeyBinding?

    private let onBindingChanged: (_ binding: HotkeyBinding, _ previous: HotkeyBinding?) -> Void
    private var settingsWatch: Task<Void, Never>?

    init(
        onTrigger: @escaping () -> Void,
        onBindingChanged: @escaping (_ binding: HotkeyBinding, _ previous: HotkeyBinding?) -> Void
    ) {
        self.onBindingChanged = onBindingChanged
        binding = KeyboardShortcuts.getShortcut(for: .toggleBormaFallback).map { _ in HotkeyBinding.fallback }

        KeyboardShortcuts.onKeyDown(for: .toggleBormaFallback, action: onTrigger)
        KeyboardShortcuts.onKeyDown(for: .toggleBorma, action: onTrigger)

        evaluateBinding()
        observeFrontmostApp()
    }

    func evaluateBinding() {
        apply(resolvedBinding())
    }

    private func resolvedBinding() -> HotkeyBinding {
        HotkeyBinding.resolve(
            saved: KeyboardShortcuts.getShortcut(for: .toggleBorma),
            cmdSpaceTaken: SpotlightConflict.isSpotlightOnCmdSpace()
        )
    }

    private func apply(_ next: HotkeyBinding) {
        switch next {
        case .fallback:
            KeyboardShortcuts.disable(.toggleBorma)
            KeyboardShortcuts.setShortcut(fallbackShortcut, for: .toggleBormaFallback)
            KeyboardShortcuts.enable(.toggleBormaFallback)
        case .saved, .unbound:
            KeyboardShortcuts.disable(.toggleBormaFallback)
            KeyboardShortcuts.setShortcut(nil, for: .toggleBormaFallback)
            KeyboardShortcuts.enable(.toggleBorma)
        }

        let previous = binding
        binding = next
        onBindingChanged(next, previous)
    }

    private var savedIsCmdSpace: Bool {
        KeyboardShortcuts.getShortcut(for: .toggleBorma) == cmdSpaceShortcut
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

    /// Re-registers only when the answer changed. `apply(_:)` briefly
    /// unregisters hot keys, so it mustn't run on every check.
    private func recheckConflict() {
        let next = resolvedBinding()
        guard next != binding else { return }
        Log.hotkey.notice("Hotkey binding changed to \(String(describing: next), privacy: .public)")
        apply(next)
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
