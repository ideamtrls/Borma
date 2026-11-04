---
scope: Global hotkey, two-name pattern, Spotlight ⌘Space conflict + fallback
globs: [Sources/Hotkey/Hotkey.swift]
keywords: [global hotkey, KeyboardShortcuts, Spotlight, conflict, fallback, two-name pattern, symbolic hotkeys, activeShortcut, saved shortcut, evaluateBinding, plist, app sandbox, container, homeDirectoryForCurrentUser, hotkey not firing, Spotlight hits ⌘Space first, conflict banner never shows, recorder change doesn't apply, wrong shortcut shown in UI]
updated: 2026-11-03
---

# Global hotkey

The global hotkey, the two-name pattern, and the Spotlight ⌘Space conflict and fallback.

## Where things live

- Controller, names, fallback constant, Spotlight check: `Sources/Hotkey/Hotkey.swift`, `HotkeyController`, `evaluateBinding()`, `fallbackShortcut`, `.toggleBorma`, `.toggleBormaFallback`, private `SpotlightConflict.isSpotlightOnCmdSpace()`
- Controller construction, `onTrigger` → `panel?.toggle()`, `onBindingChanged` → model: `Sources/App/AppDelegate.swift`, `applicationDidFinishLaunching(_:)`
- Recorder → re-evaluation: `Sources/App/BormaApp.swift`, `SettingsView` (`KeyboardShortcuts.Recorder`, `onShortcutChange`), calling `AppDelegate.refreshHotkeyBinding()`
- UI-facing state: `Sources/Search/LauncherModel.swift`, `conflictActive`, `activeHotkey`
- Bib text and conflict banner: `Sources/Panel/SearchView.swift`, `footerHintLine`, `formatShortcut(_:)`, `inputContent`, `openKeyboardSettings()`
- Sandbox setting: `Borma.entitlements`, wired by `CODE_SIGN_ENTITLEMENTS` in `project.yml`
- Library dependency: `packages.KeyboardShortcuts` in `project.yml`; source at `~/Library/Developer/Xcode/DerivedData/Borma-*/SourcePackages/checkouts/KeyboardShortcuts`
- Persisted bindings: `UserDefaults` keys `KeyboardShortcuts_toggleBorma`, `KeyboardShortcuts_toggleBormaFallback`, stored in `~/Library/Containers/com.ideamtrls.borma/Data/Library/Preferences/com.ideamtrls.borma.plist`
- Logger: `Log.hotkey` in `Sources/App/Logging.swift` (no call sites)

## Library behaviour this relies on

`HotkeyController` uses [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) (Carbon-backed via `RegisterEventHotKey`, no Accessibility permission required). `SpotlightConflict` does not use it. As of the resolved 2.4.0:

- `setShortcut(_:for:)` writes to `UserDefaults` and registers the shortcut. There is no in-memory-only binding.
- `enable` / `disable` register / unregister the Carbon hot key for the name's current `Shortcut`, by value. Neither persists anything or touches handlers.
- Key presses dispatch by value: every name whose `getShortcut(for:)` equals the pressed shortcut runs its handlers.

## Default binding

`⌘⇧Space`. Declared as:

```swift
/// ⌘⇧Space — both the out-of-box default for `.toggleBorma` and the binding
/// Borma falls back to when Spotlight still owns ⌘Space. Defined once so the
/// default and the fallback can't drift apart.
private let fallbackShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.command, .shift])

extension KeyboardShortcuts.Name {
    static let toggleBorma = Self("toggleBorma", default: fallbackShortcut)
    static let toggleBormaFallback = Self("toggleBormaFallback")
}
```

`⌘⇧Space` is the only "Spotlight + one extra modifier" combo that's unclaimed on macOS — `⌘⌥Space` is Finder search, `⌘⌃Space` is Character Viewer.

The library writes the default to `UserDefaults` the first time `.toggleBorma` is touched if the key is absent, so `getShortcut(for:)` can't tell a default from a user choice.

## Two-name pattern

`KeyboardShortcuts` has no "register a runtime override without overwriting the saved preference" primitive. Borma uses two `KeyboardShortcuts.Name` values:

- `.toggleBorma` — bound to the user's saved preference in the recorder UI.
- `.toggleBormaFallback` — no recorder, no UI surface, not a user preference. It still has a `UserDefaults` key while on the fallback, because `setShortcut` always persists. `setShortcut(nil, for:)` removes that key because the name has no default.

Both have `onKeyDown` registered to the same `onTrigger` callback. Activation is controlled by `KeyboardShortcuts.enable(_:)` / `.disable(_:)` — only one is active at a time.

This keeps the user's saved preference intact in the Settings recorder even when Borma is running on the fallback.

## Spotlight conflict

**The conflict never activates in Borma's sandboxed builds; see "Spotlight detection".** Condition 2 below is always false there, so the fallback branch and the conflict banner are unreachable.

The conflict is active when both:

1. The user's saved binding is exactly `⌘Space`, and
2. `SpotlightConflict.isSpotlightOnCmdSpace()` returns `true`.

When active:

- Borma disables `.toggleBorma` and enables `.toggleBormaFallback` with `⌘⇧Space` as its binding.
- `activeShortcut` is the binding in effect (`⌘⇧Space`), not the user's saved preference. UI that tells the user what to press must use the active value, which views read as `model.activeHotkey` (copied by `AppDelegate`'s `onBindingChanged` closure). Only the Settings recorder shows the saved value, which it reads from the library.
- `isOnFallback = true`. `AppDelegate` propagates this to `model.conflictActive` so the panel renders the conflict banner (see `panel.md`).

When not active:

- `.toggleBormaFallback` is disabled and its shortcut cleared.
- `.toggleBorma` is enabled — picks up whatever the user saved.

The recorder has its own, separate check. The library's `Shortcut.isTakenBySystem` (Carbon `CopySymbolicHotKeys`, not the plist) shows an alert when the recorded combo is an enabled system hotkey, offering OK or Use Anyway. Use Anyway saves the shortcut and is the only warning the user gets, because Borma's own detection stays silent.

## `evaluateBinding()`

Called synchronously from `init`, so `onBindingChanged` first fires before `AppDelegate.hotkey` is assigned. Also called whenever the recorder changes or clears the shortcut: the recorder's `onChange` runs `onShortcutChange`, which `BormaApp` wires to `AppDelegate.refreshHotkeyBinding()`.

Steps:

1. Read the saved binding via `KeyboardShortcuts.getShortcut(for: .toggleBorma)`.
2. Only if it is exactly `⌘Space`, check `SpotlightConflict.isSpotlightOnCmdSpace()`. The `&&` short-circuits, so any other binding never touches the plist.
3. If conflict: disable primary, set fallback shortcut, enable fallback; `activeShortcut = fallbackShortcut`, `isOnFallback = true`.
4. Otherwise: disable fallback, clear its shortcut, enable primary; `activeShortcut = saved`, `isOnFallback = false`.
5. Fire `onBindingChanged(isOnFallback, activeShortcut)`.

Step 4's shape matters because `.toggleBorma` can hold the same `⌘⇧Space` as the fallback (it's the default):

- The fallback must be cleared, not just disabled. Dispatch is by value, so a fallback left holding `⌘⇧Space` would fire `onTrigger` alongside `.toggleBorma`, and the two `PanelController.toggle()` calls cancel out.
- `.toggleBorma` must be enabled last. `disable` and `setShortcut(nil, for:)` unregister by value, which would otherwise drop the primary's hot key.

## Spotlight detection

`SpotlightConflict.isSpotlightOnCmdSpace()` builds its URL from `FileManager.default.homeDirectoryForCurrentUser` + `Library/Preferences/com.apple.symbolichotkeys.plist` and decodes it via `PropertyListSerialization`.

**In a sandboxed build that read always fails, so the function always returns `false`.** `Borma.entitlements` sets `com.apple.security.app-sandbox` with no file exceptions, and `project.yml` applies it to every configuration. `homeDirectoryForCurrentUser` is the container, `~/Library/Containers/com.ideamtrls.borma/Data`, which has no such plist (`NSCocoaErrorDomain` 260), and `try? Data(contentsOf:)` swallows the error.

The sandbox blocks the obvious alternatives too: reading the real `~/Library/Preferences/com.apple.symbolichotkeys.plist` is denied (257), and `CFPreferencesCopyAppValue` returns nil for that domain. Carbon's `CopySymbolicHotKeys` does work under the sandbox. It returns each entry's key code, modifiers, and enabled state but no hotkey id, so it can show that an enabled system hotkey holds `⌘Space`, not that the hotkey is Spotlight's.

The result: with `⌘Space` saved and Spotlight holding it, `.toggleBorma` stays registered on `⌘Space`, `isOnFallback` stays `false`, the bib shows `⌘Space`, and no banner appears.

The plist navigation, which only runs when the read succeeds:

```
top → "AppleSymbolicHotKeys" → "64" → enabled?, value.parameters
```

The `parameters` array is `[ascii, keycode, modifierMask]` (at least 3 `Int`s required). Spotlight is considered to own `⌘Space` when:

- `enabled == true`, and
- `parameters[1] == 49` (space keycode), and
- `parameters[2] == 1_048_576` (modifier mask for `⌘`).

On any read/decode/navigation failure: returns `false`. Failing open is deliberate: Borma's binding proceeds, and the worst case is the user's `⌘Space` press gets eaten by Spotlight and they figure it out themselves.

No file watcher, and the plist is read only when `evaluateBinding()` runs with `⌘Space` saved. A change to Spotlight's shortcut in System Settings while Borma is running needs a re-evaluation (relaunch Borma, or change the shortcut in Settings).

## Diagnosing a dead hotkey

- Nothing in this area logs. `Log.hotkey` has no call sites, and the plist read error is discarded.
- A failed `RegisterEventHotKey` is only `print`ed by the library. Borma still sets `activeShortcut`, so the bib can show a shortcut that isn't live.
- Clearing the recorder stores `false` under `KeyboardShortcuts_toggleBorma` (the name has a default). `getShortcut` then returns `nil`, the default is not reapplied, nothing is registered, `activeShortcut` is `nil`, and the bib shows `—`. The menu bar's Show Borma still reaches the panel.
- Handlers don't fire while the recorder has focus (`KeyboardShortcuts.isPaused`).
- Inspect saved bindings with `plutil -p` on the plist listed under "Where things live". Values are JSON with Carbon numbers: `{"carbonModifiers":256,"carbonKeyCode":49}` is `⌘Space`. `256` is Carbon's `cmdKey`, a different encoding from the `1_048_576` in the symbolic hotkeys plist.

## See also

- `panel.md` — conflict banner and bib rendering and sizing.
