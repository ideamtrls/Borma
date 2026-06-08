---
scope: System map — source layout, component graph, startup/data flow, persistence locations
globs:
  - Sources/App/BormaApp.swift
  - Sources/App/AppDelegate.swift
  - Sources/App/AppInfo.swift
  - Sources/App/Logging.swift
  - Sources/Config/Config.swift
  - Sources/Config/ConfigStore.swift
keywords: [overview, system map, source layout, component graph, data flow, persistence, atomic write, Codable version field, migration, scenes, MenuBarExtra, Settings, startup, where is X defined, what runs at startup, where does config or frecency live on disk, dismiss flow]
updated: 2026-06-07
---

# Overview

Borma is a macOS app launcher. A global hotkey summons a floating search panel; the user types, fuzzy-matched applications appear ranked by match quality and personal frecency; Enter launches the selected app; Esc dismisses.

The repo aims for a small surface area: ~1,300 lines of Swift, one external dependency (`KeyboardShortcuts`), generated via `xcodegen` from a single `project.yml`.

## Source layout

```
Sources/
├── App/        — app entry point, NSApplicationDelegate, app identity, log facility, first-run flag
├── Panel/      — floating NSPanel, SwiftUI SearchView, layout metrics
├── Search/     — app discovery, fuzzy matcher, frecency, launcher model
├── Config/     — Codable config + FSEvents file watcher
├── Hotkey/     — global hotkey controller + Spotlight conflict fallback
└── Resources/  — asset catalog, menu bar icon
```

## Component graph

```
AppDelegate
├── ConfigStore       — Observable. Loads/persists config.json.
├── FrecencyStore     — Loads/persists frecency.json. Per-(bundleId, query) launch history.
├── LauncherModel     — Observable. UI-facing state: apps, query, selection, conflict flags, active hotkey.
├── PanelController   — Owns the floating NSPanel; hosts the SwiftUI SearchView via NSHostingView.
├── HotkeyController  — Registers the global hotkey; detects ⌘Space/Spotlight conflict; falls back.
├── WelcomeFlag       — UserDefaults flag for the one-time hotkey-hint footer.
└── FileWatcher (×2)  — FSEvents wrappers for the config file and the configured app directories.

BormaApp scenes
├── MenuBarExtra      — status item with Show / Settings / Quit.
└── Settings          — SwiftUI Settings scene (hotkey recorder, launch-at-login toggle, highlight color, always-show-hint).

AppScanner            — Walks `.app` bundles into [AppRecord]. See search.md.
AppLauncher           — Opens the selected app via NSWorkspace.
Matcher               — Fuzzy subsequence scoring. See search.md.
AppInfo               — Bundle identity (`bundleID`), read from the bundle at runtime; backs the log subsystem and the Application Support dir name.
```

## Data flow

**Startup.** `AppDelegate` instantiates `ConfigStore` and `FrecencyStore`, each of which loads its JSON synchronously. On `applicationDidFinishLaunching`, the `PanelController` and `HotkeyController` are constructed, an initial scan is dispatched in the background, and two `FileWatcher`s attach: one to the config file's directory, one to the configured app directories. If the welcome flag is still active (the user has never dismissed the panel), the panel is shown immediately.

**Hotkey pressed.** `HotkeyController` invokes its `onTrigger` callback. `PanelController.toggle()` orders the panel front and makes it key (or hides it if it was already visible).

**User types.** SwiftUI publishes the query to `LauncherModel`. `results` is a computed property: score every `AppRecord` via `Matcher.score(...)`, multiply by `FrecencyStore.multiplier(...)`, sort by score (then name length, then alphabetical), take top 8.

**Return.** `LauncherModel.launchSelection()` invokes `onLaunch`. `AppDelegate` wires that to `FrecencyStore.record(query:bundleId:)` + `AppLauncher.launch(...)`. Then `onDismissRequested` fires → `PanelController.hide()`.

**Dismiss (Esc, Return-after-launch, or hotkey re-pressed).** `PanelController.hide()` calls `model.reset()`. The first `hide()` while `WelcomeFlag.isActive` retires the flag, persists it, and clears `model.welcomeActive`. Click-away does not dismiss — see `panel.md`.

**Config or app dir changes.** The corresponding `FileWatcher` yields a `Void` on its `events` `AsyncStream`. The watcher consumer reloads the config and rescans paths; `model.apps` is replaced with the new list.

## Persistence

```
~/Library/Application Support/com.ideamtrls.borma/
  config.json     — user-editable. searchPaths, highlightColor, alwaysShowHint.
                    Codable; version field for forward compat.
  frecency.json   — machine-written. entries[bundleId][query] = {launchCount, lastLaunchedAt}.
                    Versioned (currently v2); v1→v2 migration on load.
```

The `com.ideamtrls.borma` directory name isn't hardcoded — it comes from `AppInfo.bundleID` (read from the bundle at runtime), so it tracks `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` automatically.

UserDefaults key:
- `borma.welcome.dismissed` — Bool. Set true on the first panel `hide()`.

Both JSON files are written atomically (`Data.write(to:options: .atomic)`). No in-memory cache is persisted; rescans run from scratch.

When adding a new persisted store, follow the same contract: `Codable` with an explicit `version` field, atomic writes only, and a migration when you bump `version` (model it on `FrecencyStore`'s v1→v2 in `search.md`). Atomic writes also dictate how the file is watched — see `concurrency.md` ("Watch the directory, not the file").
