---
scope: NSPanel config, sizing/observation, dismissal, welcome bib, conflict banner
globs:
  - Sources/Panel/Panel.swift
  - Sources/Panel/SearchView.swift
  - Sources/Panel/LayoutMetrics.swift
  - Sources/App/WelcomeFlag.swift
keywords: [NSPanel, NSHostingView, FloatingPanel, observation tracking, withObservationTracking, layout, welcome bib, conflict banner, sizing, position, Settings adoption, dismissal, ultraThinMaterial, panel doesn't resize, panel dismisses unexpectedly, Settings opening closes the panel, click-away closes the panel, panel appears on wrong screen, welcome bib still showing after first dismiss]
updated: 2026-06-06
---

# Panel and UI

`Sources/Panel/` owns the floating search panel and everything rendered inside it.

- `Panel.swift`          — `PanelController` + `FloatingPanel` (NSPanel subclass)
- `SearchView.swift`     — SwiftUI root view inside the panel
- `LayoutMetrics.swift`  — `LauncherDimensions` (pixel constants + computed sizing)

## NSPanel configuration

`FloatingPanel` is a private `NSPanel` subclass that overrides `canBecomeKey = true` and `canBecomeMain = false`. The first lets the search field receive keystrokes; the second prevents the panel from becoming the "main" window (which would interfere with the app's `LSUIElement` behavior).

| Property | Value | Why |
|---|---|---|
| `styleMask` | `[.nonactivatingPanel, .borderless]` | Floating, no chrome |
| `level` | `.statusBar` | Floats above almost everything |
| `collectionBehavior` | `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]` | Same panel across spaces; visible in fullscreen apps; not in Cmd-Tab |
| `hidesOnDeactivate` | `false` | Don't auto-hide when another app activates — we want explicit control |
| `hasShadow` | `true`, `backgroundColor: .clear`, `isOpaque: false` | The SwiftUI view supplies its own background |

The SwiftUI root view is hosted via `NSHostingView(rootView: SearchView(...))`, set as `panel.contentView`. The hosting view's `sizingOptions = [.intrinsicContentSize]` lets it report the size SwiftUI wants.

## Sizing and live resize

Width is fixed at 640pt. Height is computed via `LauncherDimensions.inputSectionHeight(resultCount:hasConflict:)` plus the optional welcome-bib height.

`observeResults()` uses `withObservationTracking` to watch the fields that can change *while the panel is open*:

- `model.results.count`
- `model.welcomeActive`
- `model.query.isEmpty`
- `config.config.alwaysShowHint`

On any change, the panel resizes (anchored at the top — the search field stays in place, additional results extend downward) and re-installs the tracking (the `onChange` closure re-arms it; see `concurrency.md`).

`model.conflictActive` also feeds the computed height (via `inputSectionHeight(hasConflict:)`), but it is deliberately *not* in the observation set: it's established before the panel is shown — at startup, or when the user changes the hotkey — and `resize()` runs on every `show()`, so the conflict banner is already accounted for by the time the panel appears.

`LauncherDimensions` is `nonisolated` so its constants can be read from inside SwiftUI `Shape.path(in:)`, which executes off-main. See `concurrency.md`.

## Positioning

`PanelController.position()` picks the screen containing the mouse cursor and places the panel centered horizontally, vertically positioned with its center one-third from the top of the visible frame.

```swift
NSScreen.screens.first(where: mouse-in-frame)
    ?? NSScreen.main
    ?? NSScreen.screens.first!
```

The final force-unwrap crashes on zero attached displays. Rare edge case (clamshell with no external display, display-sleep transitions); if it becomes an issue, add a guard.

## Dismissal

Triggers:

- **Esc** — handled in `SearchView` (keystroke handler), routes through `model.onDismissRequested` → `panel.hide()`.
- **Return after a successful launch** — `LauncherModel.launchSelection()` invokes `onLaunch` then `onDismissRequested`.
- **Hotkey re-pressed** — `HotkeyController.onTrigger` calls `panel.toggle()`, which calls `hide()` if visible.

**Click-away does *not* dismiss the panel.** `hidesOnDeactivate = false` is set deliberately, and `panelResignedKey(_:)` doesn't call `hide()`. The panel stays visible behind whatever else gains focus until one of the triggers above fires.

## Settings adoption

When the user opens Settings (`⌘,` from the menu bar extra), the settings window becomes key and the panel briefly loses key. `panelResignedKey(_:)` notices that a *different* window has become key and adopts it as `settingsWindow`. When that window's `willClose` fires, the panel is re-ordered front via `makeKeyAndOrderFront(...)` so focus returns to the search field — without this, focus would land on the Dock or wherever else AppKit chose.

This logic only kicks in for windows owned by the app. Clicking on another app entirely leaves the panel visible but not key.

## Welcome bib retires on first dismiss

`hide()` sets `welcome.retire()` and `model.welcomeActive = false` on the first call where the flag is still active:

```swift
if welcome.isActive {
    welcome.retire()             // persists "borma.welcome.dismissed" = true
    model.welcomeActive = false  // hides the welcome bib on next show
}
```

The flag is set on `hide()`, not on app quit. A user who launches Borma but never opens the panel still sees the welcome bib on their next launch.

See `Sources/App/WelcomeFlag.swift` for the storage wrapper.

## Welcome bib and conflict banner

Two optional regions stacked below the search field + results:

- **Welcome bib** (`bibHeight = 38pt`, `bibWidth = 120pt`): rendered while `(model.welcomeActive || config.alwaysShowHint) && model.query.isEmpty`. Shows the current (active) hotkey — `formatShortcut(model.activeHotkey)`, nothing else.
- **Conflict banner** (`conflictHeight = 80pt`): rendered while `model.conflictActive`. Explains the Spotlight conflict and links to Keyboard settings.

The banner can be visible whether or not the welcome bib is. After the bib retires, the banner remains until the conflict is resolved (Spotlight is disabled / user picks a different binding). See `hotkey.md` for the conflict mechanics.
