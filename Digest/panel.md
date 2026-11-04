---
scope: NSPanel config, SwiftUI search view, sizing/observation, positioning, dismissal, Settings adoption, the bib (notch)
globs: [Sources/Panel/Panel.swift, Sources/Panel/SearchView.swift, Sources/Panel/LayoutMetrics.swift, Sources/App/WelcomeFlag.swift]
keywords: [NSPanel, NSHostingView, FloatingPanel, PanelController, SearchView, LauncherSurface, LauncherDimensions, WelcomeFlag, observation tracking, withObservationTracking, layout, welcome bib, notch, sizing, position, Settings adoption, dismissal, onKeyPress, formatShortcut, ultraThinMaterial, panel doesn't resize, panel dismisses unexpectedly, panel stays open after click-away, focus lost after Settings closes, panel appears on wrong screen, welcome bib still showing after first dismiss, panel opened by itself]
updated: 2026-11-03
---

# Panel and UI

The floating search panel and everything rendered inside it: NSPanel configuration, the SwiftUI view, sizing and live resize, positioning, dismissal, Settings adoption, and the bib.

## Where things live

- Panel lifecycle, resize, positioning, Settings adoption: `Sources/Panel/Panel.swift`, `PanelController`
- NSPanel subclass: `Sources/Panel/Panel.swift`, `FloatingPanel`
- Root view, key handling, bib rendering, hotkey text: `Sources/Panel/SearchView.swift`, `SearchView`, `formatShortcut(_:)`
- Panel silhouette: `Sources/Panel/SearchView.swift`, `LauncherSurface`
- Result rows: `Sources/Panel/SearchView.swift`, `ResultRow`
- Size constants, height formula, on-screen placement: `Sources/Panel/LayoutMetrics.swift`, `LauncherDimensions`, `inputSectionHeight(resultCount:)`, `openingY(height:fullHeight:in:)`, `clampedY(_:height:in:)`
- Welcome flag storage: `Sources/App/WelcomeFlag.swift`, `WelcomeFlag`
- Panel state and launch/dismiss logic: `Sources/Search/LauncherModel.swift`, `LauncherModel`, `launchSelection()`
- Callback wiring, show at launch and on reopen: `Sources/App/AppDelegate.swift`, `AppDelegate`
- Menu bar items, Settings scene: `Sources/App/BormaApp.swift`, `BormaApp`, `SettingsView`

## NSPanel configuration

`FloatingPanel` is a private `NSPanel` subclass that overrides `canBecomeKey = true` and `canBecomeMain = false`. The first lets the search field receive keystrokes; the second prevents the panel from becoming the "main" window (which would interfere with the app's `LSUIElement` behavior).

| Property | Value | Why |
|---|---|---|
| `styleMask` | `[.nonactivatingPanel, .borderless]` | Floating, no chrome |
| `isFloatingPanel` | `true` | Assigned before `level`, which sets the panel's level explicitly |
| `level` | `.statusBar` | Floats above almost everything, including while not key |
| `collectionBehavior` | `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]` | Same panel across spaces; visible in fullscreen apps; unaffected by Exposé; skipped by window cycling. Absence from Cmd-Tab comes from `LSUIElement`, since Cmd-Tab lists apps rather than windows |
| `hidesOnDeactivate` | `false` | Don't auto-hide when another app activates — we want explicit control |
| `hasShadow` | `true`, `backgroundColor: .clear`, `isOpaque: false` | The SwiftUI view supplies its own background |
| `isMovableByWindowBackground` | `true` | The panel can be dragged; a drag lasts until the next `show()` re-centers it |
| `isReleasedWhenClosed` | `false` | The one panel instance is reused; it is ordered out, never closed |

The SwiftUI root view is hosted via `NSHostingView(rootView: SearchView(...))`, set as `panel.contentView`, with `autoresizingMask = [.width, .height]`. The hosting view's `sizingOptions = [.intrinsicContentSize]` lets it report the size SwiftUI wants.

## Showing

`show()` runs `rememberAppBeneath()`, `model.reset()`, `resize()`, `position()`, `takeFocus()` (`NSApp.activate(ignoringOtherApps: true)` then `panel.makeKeyAndOrderFront(nil)`), and `observeResults()`, in that order. `position()` reads the height `resize()` just set. The activation is explicit because `.nonactivatingPanel` doesn't activate the app on its own.

Callers:

- **Hotkey** and the menu bar **Show Borma** item call `summon()`, which switches on `PanelPresence`. `.hidden` calls `show()`. `.unfocused` (on screen, but not the key window) calls `rememberAppBeneath()` and `takeFocus()`, keeping the query and position. `.focused` calls `hide(.cancelled)`. The hotkey is registered system-wide, so it reaches Borma whichever app has focus.
- **App launch** calls `showIfHidden()` from `applicationDidFinishLaunching(_:)` while `welcome.isActive`.
- **New hotkey conflict** calls `showIfHidden()` from `AppDelegate`'s `onBindingChanged` closure, so the user sees the hotkey that replaced theirs. `showIfHidden()` does nothing if the panel is already up, since `show()` clears the query. A conflict carried over from the last run doesn't count as new (`hotkey.md`).
- **App reopen** calls `show()` from `applicationShouldHandleReopen(_:hasVisibleWindows:)`, even if the panel is already visible, which clears the query and re-centers it.

## Sizing and live resize

Width is fixed at `panelWidth` (640pt). Height is computed via `LauncherDimensions.inputSectionHeight(resultCount:)` plus the optional bib height:

- `fieldHeight` (79pt), always
- `resultCount * rowHeight` (64pt) + `resultsPadding` (9pt), when there are results. `LauncherModel.maxResults` caps the count at 8.
- `bibHeight` (38pt), when the hint shows. `resize()` adds this; `inputSectionHeight` excludes it.

`resize()` computes the frame from these constants, and no Borma code reads the hosting view's reported size, so a new region in `SearchView` needs its height added here too. `resultsPadding` matches the results block's `Divider` plus its `.padding(.vertical, 4)`.

`observeResults()` uses `withObservationTracking` to watch:

- `model.results.count` — `results` is computed, so this registers `query`, plus `apps` when the query is non-empty. A background rescan can resize an open panel.
- `model.query.isEmpty`
- `model.welcomeActive` — written only in `PanelController.init` and in `hide(_:)` after `orderOut`, so it never resizes a visible panel.
- `model.hotkeyBinding` — `HotkeyController`'s re-checks can change it while the panel is open, which changes whether the bib shows.
- `config.config.alwaysShowHint` — registers the whole `config` property, so any change to it, from Settings or a config reload, fires.

On any change, the panel resizes without animation (anchored at the top — the search field stays in place, additional results extend downward — unless `clampedY` has to bring the panel back on screen) and re-installs the tracking. `onChange` fires once per arming, before the new value lands, so the closure defers to a main-actor `Task` (`concurrency.md` has the hop), returns if the panel isn't visible, and otherwise calls `resize()` and `observeResults()`.

`show()` arms a tracking unconditionally. A `hide(_:)` that changes nothing tracked (the query was already empty) leaves the earlier tracking armed alongside the new one. Each extra adds one redundant `resize()` per change, and all of them clear on the next hide with a typed query, because the closures then return without re-arming.

`LauncherDimensions` and `LauncherSurface` are `nonisolated`; `concurrency.md` explains why.

## Search view

`SearchView.body` is a `ZStack` with `surface` filled in `.ultraThinMaterial` behind a `VStack` of `inputContent` and the optional bib, all clipped with `.clipShape(surface)`. Top to bottom: search field, results, bib.

`LauncherSurface` draws a plain rounded rectangle (`cornerRadius`, 12pt) unless `hasBib` is true. Then it draws the input rectangle and a narrower bib joined by two concave fillets (`notchRadius`, 8pt). It falls back to the rounded rectangle when `inputHeight` isn't smaller than the rect's height.

Key handling sits on the `TextField`: `.onSubmit` calls `launchSelection()`, `.onKeyPress(.escape)` dismisses, and `.onKeyPress(.upArrow)` / `.downArrow` call `selectPrev()` / `selectNext()`. `.onAppear` sets `isFieldFocused = true`.

`ResultRow` shows the icon (`resultIconSize`, 44pt) and `displayName` at `rowHeight`, with the selected row tinted by `config.highlightColor` at 22% opacity.

`model.results` re-scores every app on each read. `body` reads it three times (`surface` twice, `inputContent` once), and `resize()` and `observeResults()` read it again.

## Positioning

`PanelController.position()` picks the screen containing the mouse cursor and places the panel centered horizontally, vertically positioned with its center one-third from the top of the visible frame (`LauncherDimensions.openingY`). On a short screen it sits higher, so a full result list fits below the search field without the field moving as results appear. `resize()` also applies `clampedY`, which brings a panel dragged near an edge back onto its screen. A panel too tall for the screen stays aligned to the top, keeping the search field reachable.

```swift
NSScreen.screens.first(where: mouse-in-frame)
    ?? NSScreen.main
    ?? NSScreen.screens.first!
```

The final force-unwrap crashes on zero attached displays. Rare edge case (clamshell with no external display, display-sleep transitions); if it becomes an issue, add a guard.

## Dismissal

`hide(_:)` runs `panel.orderOut(nil)`, `model.reset()`, the welcome retire step, and `returnFocus(after:)`. Its `PanelDismissal` argument decides where focus goes:

- `.launching` — the launched app takes focus itself.
- `.cancelled` — `appBeneath` is activated. `rememberAppBeneath()` records it each time the panel takes focus through `show()` or `summon()`, before Borma activates, and it stays `nil` when the panel opened over Borma itself. Nothing is activated if Borma is no longer active, because the user has already moved to another app, or if `settingsWindow` is set, because Settings keeps focus.

Triggers:

- **Esc** — `.onKeyPress(.escape)` on the `TextField` calls `model.onDismissRequested` with `.cancelled`, which `AppDelegate` wires to `panel.hide(_:)`.
- **Return** — `.onSubmit` calls `LauncherModel.launchSelection()`. If `selectedApp(in:)` finds an app, it invokes `onLaunch` then `onDismissRequested` with `.launching`; otherwise (empty query, no matches) it invokes only `onDismissRequested`, with `.cancelled`. The launch outcome isn't checked: `AppLauncher.launch` is asynchronous and a failure logs and beeps after the panel is gone.
- **Click on a result row** — `.onTapGesture` sets `model.selection` and calls `launchSelection()`.
- **Hotkey re-pressed while focused** — `HotkeyController` runs its `onTrigger` closure, which `AppDelegate` wires to `panel.summon()`; `summon()` calls `hide(.cancelled)` when the panel is `.focused`.
- **Show Borma menu item** — also `summon()`, so it hides a focused panel.

**Click-away does *not* dismiss the panel.** `hidesOnDeactivate = false` is set deliberately, and `panelResignedKey(_:)` doesn't call `hide(_:)`. The panel stays on screen at `.statusBar` level, above normal windows but not key, until one of the triggers above fires. Keystrokes go to the new key window, so Esc and Return don't reach it. The hotkey gives it focus back with the query intact, and cancelling then returns focus to the app that was frontmost when the hotkey was pressed.

## Settings adoption

The menu bar extra's **Settings…** item (shortcut `⌘,`) activates Borma and then calls `openSettings()`, because a menu click doesn't activate an accessory app. When the user opens Settings with the panel open, the settings window becomes key and the panel loses key for as long as that window holds it. `panelResignedKey(_:)` notices that a *different* window has become key and adopts it as `settingsWindow`. The check runs in a `Task` because AppKit hasn't installed the new key window when the notification fires, and it is skipped while `settingsWindow` is set. When that window's `willClose` fires, `settingsWindowWillClose(_:)` clears `settingsWindow` and, if the panel is still visible, calls `NSApp.activate(ignoringOtherApps: true)` and `makeKeyAndOrderFront(...)` so focus returns to the search field — without this, focus would land on the Dock or wherever else AppKit chose.

This logic only kicks in for windows owned by the app, and it adopts any of them: the check is `NSApp.keyWindow !== panel`, not a test for the Settings window. Clicking on another app entirely leaves the panel visible but not key.

## Welcome bib retires on first dismiss

`PanelController.init` seeds `model.welcomeActive` from `welcome.isActive`. `hide(_:)` retires the flag on the first call where it is still active:

```swift
if welcome.isActive {
    welcome.retire()             // persists "borma.welcome.dismissed" = true
    model.welcomeActive = false  // from here the bib needs alwaysShowHint or a conflict
}
```

The flag is set on `hide(_:)`, not on app quit. While it is active the panel opens itself at launch, so a user who quits without dismissing the panel sees it and the welcome bib again on their next launch.

## The bib

The notch hanging off the bottom of the panel (`bibHeight = 38pt`, `bibWidth = 120pt`). Rendered while `(model.welcomeActive || model.hotkeyBinding == .fallback || config.config.alwaysShowHint) && model.query.isEmpty`. That expression exists twice, in `SearchView.shouldShowHint` and `PanelController.resize()`, and the two must match. `alwaysShowHint` is the Settings **Always show hotkey** toggle. Shows the current (active) hotkey — `formatShortcut(model.hotkeyBinding?.shortcut)`, nothing else. Keep it to that: during a conflict the panel carries no explanation or settings link, by design. Results and the bib never coexist, since `results` is empty for an empty query.

`formatShortcut(_:)` joins `⌃ ⌥ ⇧ ⌘` and the key name with ` + `, shows Space as `␣`, and returns `—` for a nil shortcut. `KeyboardShortcuts` has no public key-glyph helper, so it recovers the key name by stripping modifier glyphs from `shortcut.description`.

## See also

- `concurrency.md` — `-default-isolation MainActor` and the `nonisolated` rules for `Shape` code.
- `hotkey.md` — conflict detection and the fallback binding.
