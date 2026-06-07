---
scope: Global hotkey, two-name pattern, Spotlight ⌘Space conflict + fallback
globs:
  - Sources/Hotkey/Hotkey.swift
keywords: [global hotkey, KeyboardShortcuts, Spotlight, conflict, fallback, two-name pattern, symbolic hotkeys, activeShortcut, savedShortcut, evaluateBinding, plist, hotkey not firing, Spotlight hits ⌘Space first, recorder change doesn't apply, fallback stuck on after Spotlight disabled, wrong shortcut shown in UI]
updated: 2026-06-06
---

# Global hotkey

`Sources/Hotkey/Hotkey.swift` owns `HotkeyController` and the private `SpotlightConflict` helper. Both use the [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) library (Carbon-backed, no Accessibility permission required).

## Default binding

`⌘⇧Space`. Registered as:

```swift
// One constant feeds both the out-of-box default for `.toggleBorma` and the
// runtime fallback binding, so the two can't drift apart.
private let fallbackShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.command, .shift])

extension KeyboardShortcuts.Name {
    static let toggleBorma = Self("toggleBorma", default: fallbackShortcut)
    static let toggleBormaFallback = Self("toggleBormaFallback")
}
```

`⌘⇧Space` is the only "Spotlight + one extra modifier" combo that's unclaimed on macOS — `⌘⌥Space` is Finder search, `⌘⌃Space` is Character Viewer.

## Two-name pattern

`KeyboardShortcuts` has no "register a runtime override without overwriting the saved preference" primitive. Borma uses two `KeyboardShortcuts.Name` values:

- `.toggleBorma` — bound to the user's saved preference in the recorder UI.
- `.toggleBormaFallback` — runtime-only; no recorder, no UI surface.

Both have `onKeyDown` registered to the same `onTrigger` callback. Activation is controlled by `KeyboardShortcuts.enable(_:)` / `.disable(_:)` — only one is active at a time.

This keeps the user's saved preference intact in the Settings recorder even when Borma is running on the fallback.

## Spotlight conflict

The conflict is active when both:

1. The user's saved binding is `⌘Space`, and
2. Spotlight's symbolic hotkey `#64` is enabled and bound to `⌘Space`.

When active:

- Borma disables `.toggleBorma` and enables `.toggleBormaFallback` with `⌘⇧Space` as the runtime binding.
- `activeShortcut` reflects what's *actually* registered (`⌘⇧Space`), not the user's saved preference.
- `isOnFallback = true`. `AppDelegate` propagates this to `model.conflictActive` so the panel renders the conflict banner (see `panel.md`).

When not active:

- `.toggleBormaFallback` is disabled and its runtime shortcut cleared.
- `.toggleBorma` is enabled — picks up whatever the user saved.

## `evaluateBinding()`

Called at construction and whenever the user changes the shortcut in the Settings recorder (the recorder's `onChange` is wired through `AppDelegate.refreshHotkeyBinding()` in `BormaApp.swift`).

Steps:

1. Read the saved binding via `KeyboardShortcuts.getShortcut(for: .toggleBorma)`.
2. Check `SpotlightConflict.isSpotlightOnCmdSpace()`.
3. If conflict: disable primary, set fallback runtime shortcut, enable fallback.
4. Otherwise: clear fallback runtime, disable fallback, enable primary.
5. Update `activeShortcut` / `isOnFallback`, fire `onBindingChanged`.

## Spotlight detection

`SpotlightConflict.isSpotlightOnCmdSpace()` reads `~/Library/Preferences/com.apple.symbolichotkeys.plist` and decodes it via `PropertyListSerialization`. Navigates:

```
top → "AppleSymbolicHotKeys" → "64" → enabled?, value.parameters
```

The `parameters` array is `[ascii, keycode, modifierMask]`. Spotlight is considered to own `⌘Space` when:

- `enabled == true`, and
- `parameters[1] == 49` (space keycode), and
- `parameters[2] == 1_048_576` (modifier mask for `⌘`).

On any decode/navigation failure: returns `false`. The user is allowed to bind `⌘Space` even if we can't verify Spotlight's state — the worst case is the user's `⌘Space` press gets eaten by Spotlight and they figure it out themselves.

No file watcher; the plist is read at each `evaluateBinding()` call. If a user disables Spotlight in System Settings while Borma is running, they need to trigger a re-evaluation (relaunch Borma, or commit a new shortcut in Settings).
