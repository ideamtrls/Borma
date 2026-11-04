---
scope: System map — source layout, component graph, startup and data flow, config schema, on-disk persistence locations, logging
globs: [Sources/App/BormaApp.swift, Sources/App/AppDelegate.swift, Sources/App/AppInfo.swift, Sources/App/Logging.swift, Sources/Config/Config.swift, Sources/Config/ConfigStore.swift]
keywords: [overview, system map, source layout, component graph, data flow, persistence, sandbox, container, Application Support, UserDefaults, config.json, config.json.errors, frecency.json, atomic write, Codable version field, migration, scenes, MenuBarExtra, Settings, launch at login, startup, Log, logging, AppInfo, bundle id, where is X defined, what runs at startup, where does config or frecency live on disk, config edit has no effect, config reset to defaults, dismiss flow]
updated: 2026-11-03
---

# Overview

System map of Borma: source layout, component graph, startup and data flow, config schema, on-disk persistence locations, logging.

Borma is a macOS app launcher. A global hotkey summons a floating search panel; the user types, fuzzy-matched applications appear ranked by match quality and personal frecency; Enter launches the selected app; Esc dismisses. It runs as an agent app (`INFOPLIST_KEY_LSUIElement`) with no Dock icon, so its only entry points are the hotkey, the menu bar item, and reopening the app.

The repo aims for a small surface area: ~1,400 lines of Swift, one external dependency (`KeyboardShortcuts`), generated via `xcodegen` from a single `project.yml`.

## Where things live

- App entry point, menu bar item, Settings window: `Sources/App/BormaApp.swift`, `BormaApp`, private `SettingsView`
- Object wiring, startup, rescan, watcher attachment: `Sources/App/AppDelegate.swift`, `AppDelegate.applicationDidFinishLaunching(_:)`, `rescan()`, `startConfigWatcher()`, `startAppWatcher()`
- Data directory resolution: `Sources/App/AppDelegate.swift`, file-private `appSupportDir()`
- Bundle identity: `Sources/App/AppInfo.swift`, `AppInfo.bundleID`
- Log categories: `Sources/App/Logging.swift`, `Log`
- First-run flag: `Sources/App/WelcomeFlag.swift`, `WelcomeFlag`
- Config schema and defaults: `Sources/Config/Config.swift`, `Config`, `Config.default`, `HexColor`
- Config load, reload, save, broken-file handling: `Sources/Config/ConfigStore.swift`, `ConfigStore.load()`, `ConfigStore.reload()`, `ConfigStore.save()`, `preserveBrokenFile()`
- FSEvents wrapper: `Sources/Config/FileWatcher.swift`, `FileWatcher`
- Panel and its view: `Sources/Panel/Panel.swift`, `PanelController`; `Sources/Panel/SearchView.swift`, `SearchView`
- Hotkey and Spotlight check: `Sources/Hotkey/Hotkey.swift`, `HotkeyController`, `SpotlightConflict`
- Search session state: `Sources/Search/LauncherModel.swift`, `LauncherModel`
- App scanning and launching: `Sources/Search/Apps.swift`, `AppScanner`, `AppLauncher`, `AppRecord`
- Match scoring: `Sources/Search/Matcher.swift`, `Matcher`
- Launch history: `Sources/Search/FrecencyStore.swift`, `FrecencyStore`
- Sandbox and bundle id settings: `Borma.entitlements`; `project.yml`, `CODE_SIGN_ENTITLEMENTS`, `PRODUCT_BUNDLE_IDENTIFIER`

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
├── LauncherModel     — Observable. UI-facing state: apps, query, selection, welcome flag, hotkey binding; computes results.
├── PanelController   — Owns the floating NSPanel; hosts the SwiftUI SearchView via NSHostingView.
├── HotkeyController  — Registers the global hotkey; detects a ⌘Space conflict and falls back.
├── WelcomeFlag       — UserDefaults flag for the one-time hotkey-hint footer.
└── FileWatcher (×2)  — FSEvents wrappers for the config file's directory and the configured app directories.

BormaApp scenes
├── MenuBarExtra      — status item with Show / Settings / Quit. "Show Borma" calls summon(), the same as the hotkey.
└── Settings          — SwiftUI Settings scene (hotkey recorder, launch-at-login toggle, always-show-hint, system-accent toggle + highlight color). Edits save through .onChange(of: config.config).

AppScanner            — Walks `.app` bundles into [AppRecord]. See search.md.
AppLauncher           — Opens the selected app via NSWorkspace.
Matcher               — Fuzzy subsequence scoring. See search.md.
AppInfo               — Bundle identity (`bundleID`), read from the bundle at runtime; backs the log subsystem and the Application Support dir name.
```

## Data flow

**Startup.** `AppDelegate` instantiates `ConfigStore` and `FrecencyStore`, each of which loads its JSON synchronously; `appSupportDir()` creates the data directory if needed. On `applicationDidFinishLaunching`, the `PanelController` and `HotkeyController` are constructed, an initial scan is dispatched in the background, and two `FileWatcher`s attach: one to the config file's directory, one to the configured app directories (none when `searchPaths` is empty). The panel is shown immediately if the welcome flag is still active (the user has never dismissed the panel) or the hotkey was taken since the last run.

**Hotkey taken.** `HotkeyController` re-checks on every app switch. A new conflict moves Borma to the fallback hotkey and opens the panel, whose bib shows it. See `hotkey.md`.

**Reopen.** Launching the already-running app calls `applicationShouldHandleReopen`, which calls `PanelController.show()`.

**Hotkey pressed.** `HotkeyController` invokes its `onTrigger` callback, whichever app has focus. `PanelController.summon()` opens a hidden panel, gives focus to a panel that's on screen without it (keeping the query), and hides a focused one. The menu bar's "Show Borma" calls the same `summon()`.

**User types.** SwiftUI publishes the query to `LauncherModel`, and editing it clears `selection`, returning the highlight to the top result. `results` is a computed property, empty for an empty query: score each `AppRecord`'s display name and file name via `Matcher.score(...)` and keep the better one (apps matching neither drop out), floor that at 1, multiply by `FrecencyStore.multiplier(...)`, sort by score (then name length, then alphabetical), take top 8 (`LauncherModel.maxResults`).

**Return.** Return or a row click calls `LauncherModel.launchSelection()`, which invokes `onLaunch`. `AppDelegate` wires that to `FrecencyStore.record(query:bundleId:)` + `AppLauncher.launch(...)`. Then `onDismissRequested` fires → `PanelController.hide(_:)`. With no result to launch, only the dismiss fires.

**Dismiss (Esc, Return or row click, or hotkey / "Show Borma" while focused).** `PanelController.hide(_:)` orders the panel out and calls `model.reset()`. The first `hide(_:)` while `WelcomeFlag.isActive` retires the flag, persists it, and clears `model.welcomeActive`. A dismiss that launched nothing hands focus back to the app the panel opened over. Click-away does not dismiss — see `panel.md`.

**Config or app dir changes.** The corresponding `FileWatcher` yields a `Void` on its `events` `AsyncStream`. The config watcher covers the whole App Support directory (see `concurrency.md`), so frecency saves and `ConfigStore`'s own writes fire it too; the consumer reloads the config and only rescans + re-attaches the app watcher when the reloaded `Config` differs (`Config` is `Equatable`). Settings edits update the in-memory `Config` before saving, so they reload equal. That includes colors, because `HexColor` holds the same 8 bits per channel in memory as `#RRGGBB` does on disk. App-dir events always trigger a rescan; `model.apps` is replaced with the new list.

## Persistence

```
~/Library/Containers/com.ideamtrls.borma/Data/Library/Application Support/com.ideamtrls.borma/
  config.json     — user-editable. searchPaths, highlightColor, alwaysShowHint.
                    Codable; version is written as 1 and nothing reads it. If it
                    fails to decode (bad hand edit), it's moved aside to
                    config.json.errors and the config in memory is written:
                    defaults at startup, the last good values after that.
  frecency.json   — machine-written launch history, absent until the first recorded
                    launch. Schema, migration, pruning, and failure handling: search.md.
```

**That path is inside the sandbox container, although the code reads like a plain Application Support lookup.** `Borma.entitlements` sets `com.apple.security.app-sandbox` and `project.yml` applies it through `CODE_SIGN_ENTITLEMENTS` for every configuration, so `appSupportDir()`'s `.applicationSupportDirectory` lookup resolves under `~/Library/Containers/com.ideamtrls.borma/Data/Library/`. A sandboxed build never reads `~/Library/Application Support/com.ideamtrls.borma/`, so a `config.json` edited there has no effect. A build made with `CODE_SIGNING_ALLOWED=NO` (see `build.md`) carries no entitlements, runs unsandboxed, and does use that path.

The bundle id appears twice in the path and neither use is hardcoded: macOS names the container after it, and the inner directory comes from `AppInfo.bundleID` (read from the bundle at runtime; the literal in `AppInfo` is a fallback for non-bundled contexts). Both track `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`; `build.md` covers what changing it does.

UserDefaults live in the same container (`Data/Library/Preferences/com.ideamtrls.borma.plist`); `defaults read com.ideamtrls.borma` reaches them from a normal shell. Keys:
- `borma.welcome.dismissed` — Bool, owned by `WelcomeFlag`. Set true on the first panel `hide(_:)`.
- `KeyboardShortcuts_toggleBorma` — the user's hotkey, a JSON string written by the `KeyboardShortcuts` package. Seeded with ⌘⇧Space by the `default:` on `.toggleBorma`.
- `KeyboardShortcuts_toggleBormaFallback` — exists only while the Spotlight fallback is active.

Borma stores no launch-at-login state: `SettingsView` reads and sets it through `SMAppService.mainApp` and holds the `SMAppService.Status` it read last. The toggle is on only for `.enabled`. While the status is `.requiresApproval`, a button opens System Settings' Login Items, and the status is re-read whenever Borma becomes active. A failed change logs and beeps once, and every attempt refreshes the status.

Both JSON files are written atomically (`Data.write(to:options: .atomic)`). No in-memory cache is persisted; rescans run from scratch.

When adding a new persisted store, follow the same contract: `Codable` with an explicit `version` field, atomic writes only, and a migration when you bump `version` (model it on `FrecencyStore`'s v1→v2 in `search.md`).
## Config schema

`Config` has a hand-written `init(from:)`, and `Config.default` supplies the out-of-box values.

- `version`, `searchPaths`: required. A file missing either fails decode. Default paths are `/Applications` and `/System/Applications`.
- `highlightColor`: optional `HexColor`, stored as a `#RRGGBB` string and held in memory as three `UInt8`s. Absent means the system accent color. A malformed value fails decode for the whole file.
- `alwaysShowHint`: optional, defaults to `false`.

**Adding a setting.** Decode the new field with `decodeIfPresent` and a default in `init(from:)`, then add its control to `SettingsView`. A required key fails decode on every existing file, which moves the user's config aside and resets it.

**`searchPaths` entries are used literally.** They reach `URL(fileURLWithPath:)` and `FileWatcher` unmodified, so `~` isn't expanded. The sandbox also limits which roots can work; see `build.md` ("App sandbox at runtime").

**Reading the config.** `load()` runs once at startup and acts on the file as it is. `reload()` runs on every config-watcher event; a malformed read may be an editor's half-finished save, so it reads again after `partialWriteGrace` (500 ms) before acting. Both go through the private `ReadResult` enum:
- `.missing`: writes the in-memory config, which is the defaults at startup and the last-loaded values if the file is deleted while running.
- `.loaded`: replaces the in-memory config.
- `.malformed`, any `DecodingError` including JSON syntax errors: `preserveBrokenFile()` moves the file to `config.json.errors` (replacing any earlier one), then the in-memory config is saved, which is the defaults at startup and the last good values while running. If the move throws, the error is logged and the file is left in place.
- `.unreadable`, any other read error: logged, with the in-memory config and the file left alone.

## Logging

`Log` has one `Logger` per category (`app`, `config`, `frecency`, `hotkey`, `scanner`), all under subsystem `AppInfo.bundleID`. `Log.scanner` has no call sites; `AppLauncher` and `FileWatcher` log through `Log.app`. To watch: `log stream --predicate 'subsystem == "com.ideamtrls.borma"'`.

## See also

- `build.md` — signing and the sandbox entitlement that decides the paths above
- `concurrency.md` — `FileWatcher` internals and directory watching
- `search.md` — scanning, scoring, and frecency, including the v1→v2 migration
