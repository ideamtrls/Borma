---
scope: Global hotkey, two-name pattern, Spotlight ⌘Space conflict + fallback
globs: [Sources/Hotkey/Hotkey.swift]
keywords: [global hotkey, KeyboardShortcuts, Spotlight, conflict, fallback, two-name pattern, symbolic hotkeys, CopySymbolicHotKeys, HotkeyBinding, saved shortcut, evaluateBinding, recheckConflict, app switch re-check, hotkey not firing, Borma and Spotlight both open, recorder change doesn't apply, wrong shortcut shown in UI]
updated: 2026-11-03
---

# Global hotkey

The global hotkey, the two-name pattern, and the Spotlight ⌘Space conflict and fallback.

## Where things live

- Binding state, controller, names, fallback constant, Spotlight check: `Sources/Hotkey/Hotkey.swift`, `HotkeyBinding`, `HotkeyController`, `evaluateBinding()`, `fallbackShortcut`, `.toggleBorma`, `.toggleBormaFallback`, `recheckConflict()`, `frontmostAppDidChange(to:)`, private `SpotlightConflict.isSpotlightOnCmdSpace()`
- Controller construction, `onTrigger` → `panel?.summon()`, `onBindingChanged` → model, plus `panel?.showIfHidden()` on a new conflict: `Sources/App/AppDelegate.swift`, `applicationDidFinishLaunching(_:)`
- Recorder → re-evaluation: `Sources/App/BormaApp.swift`, `SettingsView` (`KeyboardShortcuts.Recorder`, `onShortcutChange`), calling `AppDelegate.refreshHotkeyBinding()`
- UI-facing state: `Sources/Search/LauncherModel.swift`, `hotkeyBinding`
- Bib text: `Sources/Panel/SearchView.swift`, `footerHintLine`, `formatShortcut(_:)`
- Library dependency: `packages.KeyboardShortcuts` in `project.yml`; source at `~/Library/Developer/Xcode/DerivedData/Borma-*/SourcePackages/checkouts/KeyboardShortcuts`
- Persisted bindings: `UserDefaults` keys `KeyboardShortcuts_toggleBorma`, `KeyboardShortcuts_toggleBormaFallback`, stored in `~/Library/Containers/com.ideamtrls.borma/Data/Library/Preferences/com.ideamtrls.borma.plist`
- Logger: `Log.hotkey` in `Sources/App/Logging.swift`

## Library behaviour this relies on

`HotkeyController` uses [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) (Carbon-backed via `RegisterEventHotKey`, no Accessibility permission required). `SpotlightConflict` does not use it. `project.yml` pins 2.4.0, where:

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

When Borma and Spotlight both hold `⌘Space`, both receive the press and both open, so Borma must not hold `⌘Space` during a conflict.

The conflict is active when both:

1. The user's saved binding is exactly `⌘Space`, and
2. `SpotlightConflict.isSpotlightOnCmdSpace()` returns `true`.

When active:

- Borma disables `.toggleBorma` and enables `.toggleBormaFallback` with `⌘⇧Space` as its binding.
- `binding` is `.fallback`, whose `shortcut` is `⌘⇧Space`, not the user's saved preference. UI that tells the user what to press must use the binding's shortcut, which views read as `model.hotkeyBinding?.shortcut` (copied by `AppDelegate`'s `onBindingChanged` closure). Only the Settings recorder shows the saved value, which it reads from the library.
- `AppDelegate` propagates the binding to `model.hotkeyBinding`, which keeps the bib visible while it's `.fallback`. When `isNewConflict(since:)` says the conflict is new, it opens the panel unless the panel is already up, so the user sees the active hotkey without losing what they're typing (see `panel.md`).
- A conflict carried over from the last run isn't new. `.toggleBormaFallback` has a stored shortcut only while on the fallback, so `HotkeyController.init` seeds `binding` from it. A conflict that began while Borma wasn't running is new.

When not active:

- `.toggleBormaFallback` is disabled and its shortcut cleared.
- `.toggleBorma` is enabled — picks up whatever the user saved.

The recorder has its own, separate check. The library's `Shortcut.isTakenBySystem` (Carbon `CopySymbolicHotKeys`, not the plist) shows an alert when the recorded combo is an enabled system hotkey, offering OK or Use Anyway. Use Anyway saves the shortcut, and Borma then moves to the fallback.

## `evaluateBinding()`

Called synchronously from `init`, so `onBindingChanged` first fires before `AppDelegate.hotkey` is assigned. Also called whenever the recorder changes or clears the shortcut: the recorder's `onChange` runs `onShortcutChange`, which `BormaApp` wires to `AppDelegate.refreshHotkeyBinding()`. `recheckConflict()` runs the same `apply(_:)` when the resolved binding changes.

Steps:

1. Read the saved binding via `KeyboardShortcuts.getShortcut(for: .toggleBorma)`.
2. `HotkeyBinding.resolve(saved:cmdSpaceTaken:)` decides the binding. Only if the saved binding is exactly `⌘Space` does it check `SpotlightConflict.isSpotlightOnCmdSpace()`: `cmdSpaceTaken` is an `@autoclosure` behind `&&`, so any other binding never calls Carbon.
3. `.fallback`: disable primary, set fallback shortcut, enable fallback.
4. `.saved` or `.unbound`: disable fallback, clear its shortcut, enable primary.
5. Store the result in `binding` and fire `onBindingChanged(binding, previous)`.

Step 4's shape matters because `.toggleBorma` can hold the same `⌘⇧Space` as the fallback (it's the default):

- The fallback must be cleared, not just disabled. Dispatch is by value, so a fallback left holding `⌘⇧Space` would fire `onTrigger` alongside `.toggleBorma`, running `PanelController.summon()` twice per press.
- `.toggleBorma` must be enabled last. `disable` and `setShortcut(nil, for:)` unregister by value, which would otherwise drop the primary's hot key.

## Spotlight detection

`SpotlightConflict.isSpotlightOnCmdSpace()` calls Carbon's `CopySymbolicHotKeys` and returns `true` when an enabled entry has key code `kVK_Space` and modifiers `cmdKey`. A call takes about 3 ms. On failure it logs and returns `false`, so Borma's binding proceeds.

Entries carry no hotkey id, so this detects any enabled system hotkey on `⌘Space`, not Spotlight's specifically. Spotlight is the default holder, and the fallback is right whichever one it is.

This is the route that works under the App Sandbox. `~/Library/Preferences/com.apple.symbolichotkeys.plist` is unusable: `homeDirectoryForCurrentUser` is the container, which has no such file (`NSCocoaErrorDomain` 260), the real path is denied (257), and `CFPreferencesCopyAppValue` returns nil for that domain. The plist also lags, updating 4–7 seconds after a change, while `CopySymbolicHotKeys` reflects it within a second in a running process.

## Re-checking

macOS posts no observable notification when a symbolic hotkey changes, so `HotkeyController` re-checks on two triggers:

- **Every app switch** (`NSWorkspace.didActivateApplicationNotification`). Summoning Borma counts as a switch.
- **Once a second while System Settings is frontmost and `⌘Space` is saved** (`settingsWatch`). No app switch follows a change made there, so `⌘Space` pressed right after freeing it would otherwise do nothing. The watch ends at the next app switch.

`recheckConflict()` calls `apply(_:)` only when the resolved binding differs from `binding`, because `apply(_:)` unregisters and re-registers hot keys.

## Diagnosing a dead hotkey

- `Log.hotkey` records conflict changes and `CopySymbolicHotKeys` failures. Nothing else in this area logs.
- A failed `RegisterEventHotKey` is only `print`ed by the library. Borma still sets `binding`, so the bib can show a shortcut that isn't live.
- Clearing the recorder stores `false` under `KeyboardShortcuts_toggleBorma` (the name has a default). `getShortcut` then returns `nil`, the default is not reapplied, nothing is registered, `binding` is `.unbound`, and the bib shows `—`. The menu bar's Show Borma still reaches the panel.
- Handlers don't fire while the recorder has focus (`KeyboardShortcuts.isPaused`).
- Inspect saved bindings with `plutil -p` on the plist listed under "Where things live". Values are JSON with Carbon numbers: `{"carbonModifiers":256,"carbonKeyCode":49}` is `⌘Space`. `256` is Carbon's `cmdKey`.

## See also

- `panel.md` — bib rendering and sizing.
