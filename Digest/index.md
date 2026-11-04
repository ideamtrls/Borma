---
scope: Reverse map from source file to covering digest, plus a task index of dev commands and change recipes
globs: []
keywords: [index, navigation, reverse map, which digest covers this file, can't find the right digest, task index, dev commands, reset frecency, reset config, reset welcome bib, force Spotlight conflict, config schema change, frecency schema migration, add a setting, add a source file, add a log category, view logs, version bump, publish to TestFlight]
updated: 2026-11-04
---

# Digest index

Reverse map from source file to covering digest, plus a task index of dev commands and change recipes.

## By source file (reverse map)

The primary doc is the one whose `globs` claim the file and that owns the deep explanation.

| Source file | Primary doc | Also covered in |
| --- | --- | --- |
| `Sources/App/BormaApp.swift` | `overview.md` (Scenes, MenuBarExtra, Settings) | `hotkey.md` (Recorder→`refreshHotkeyBinding`) |
| `Sources/App/AppDelegate.swift` | `overview.md` (component graph, data flow) | `search.md` (model wiring), `concurrency.md` (watcher attach and reassign), `hotkey.md` (binding callback) |
| `Sources/App/Logging.swift` | `overview.md` (`Log` categories, subsystem) | `CLAUDE.md` header (the `Log.<category>` rule) |
| `Sources/App/AppInfo.swift` | `overview.md` (bundle identity; backs log subsystem + App Support dir) | — |
| `Sources/App/WelcomeFlag.swift` | `panel.md` (welcome bib retire-on-hide) | `glossary.md`, `overview.md` (UserDefaults key) |
| `Sources/Panel/Panel.swift` | `panel.md` (NSPanel, sizing, observation re-arm, Settings adoption) | `glossary.md` (observation re-arm), `concurrency.md` (`onChange` hop) |
| `Sources/Panel/SearchView.swift` | `panel.md` (rendering, hotkey formatting) | `hotkey.md` (active hotkey), `concurrency.md` (`nonisolated` `Shape`) |
| `Sources/Panel/LayoutMetrics.swift` | `panel.md` (sizing) | `concurrency.md` (`nonisolated` for `Shape`) |
| `Sources/Config/Config.swift` | `overview.md` (persistence shape) | — |
| `Sources/Config/ConfigStore.swift` | `overview.md` (persistence) | `panel.md` (`alwaysShowHint` observation), `concurrency.md` (atomic saves, directory watch) |
| `Sources/Config/FileWatcher.swift` | `concurrency.md` (`ContinuationBox`) | `overview.md` (data flow), `glossary.md` |
| `Sources/Search/Apps.swift` | `search.md` (`AppScanner`, `AppLauncher`) | `concurrency.md` (off-main scan, `Sendable`) |
| `Sources/Search/Matcher.swift` | `search.md` (scoring constants) | `concurrency.md` (default isolation) |
| `Sources/Search/FrecencyStore.swift` | `search.md` (formula, migration) | `glossary.md`, `overview.md` (on-disk location) |
| `Sources/Search/LauncherModel.swift` | `search.md` (orchestrator) | `panel.md` (observation surface) |
| `Sources/Hotkey/Hotkey.swift` | `hotkey.md` (controller, Spotlight detection) | `glossary.md` (two-name pattern, active vs. saved) |
| `Sources/Resources/Assets.xcassets` | `build.md` (`AppIcon`, `MenuBarIcon`) | — |
| `project.yml` | `build.md` (xcodegen) | `concurrency.md` (`-default-isolation MainActor`), `overview.md` (bundle id) |
| `Borma.entitlements` | `build.md` (app sandbox, signing) | `overview.md` (data paths) |
| `Scripts/upload.sh`, `Scripts/distribute.swift` | `build.md` (TestFlight uploads) | — |

## Task index

Paths below assume a signed build, which runs in the App Sandbox; `overview.md` ("Persistence") has the layout.

Reset commands need Borma quit, because a running app undoes them: `FrecencyStore.record()` re-saves its whole in-memory history, the config watcher's `ConfigStore.reload()` writes a missing `config.json` straight back, and the next `PanelController.hide(_:)` re-retires the welcome flag.

| When you want to… | Read or run |
| --- | --- |
| Add a new persisted user setting or Settings toggle | `overview.md` (Config schema), `Sources/Config/Config.swift`, `SettingsView` in `Sources/App/BormaApp.swift` |
| Add a new source file | Run `xcodegen generate` afterward: the generated project lists each `Sources/` file individually, so a new one isn't in the build until then (`build.md`) |
| Add a new SwiftUI view inside the panel | `panel.md` (NSHostingView, observation re-arm); state that changes the panel's height must also be read in `PanelController.observeResults()` |
| Adopt a new external SPM dependency | `build.md` (`project.yml` `packages:` and the target's `dependencies:`), then `xcodegen generate` |
| Bump the app version | `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, then `xcodegen generate` |
| Change panel sizing or positioning | `panel.md`, `concurrency.md` (`Shape` isolation) |
| Change the default hotkey | `hotkey.md`; `fallbackShortcut` in `Sources/Hotkey/Hotkey.swift` is both the `.toggleBorma` default and the Spotlight fallback |
| Diagnose a hotkey-not-firing bug | `hotkey.md` (conflict + fallback) |
| Force a Spotlight conflict in dev | Both conditions must hold: the saved binding is ⌘Space (record it in Settings, choosing "Use Anyway" if Spotlight holds it) and Spotlight's shortcut is enabled on ⌘Space (System Settings → Keyboard → Keyboard Shortcuts → Spotlight). Within a second Borma moves to the fallback and opens the panel |
| Migrate the frecency on-disk schema | `search.md` (`FrecencyStore` migration). Bump `FrecencyData.currentVersion`, add a legacy struct and a branch in `FrecencyStore.load()`, and model the conversion on `FrecencyDataV1.migrated()`. A file no branch decodes leaves history empty, and the next save overwrites it |
| Migrate the config on-disk schema | `Sources/Config/Config.swift`; `overview.md` (Config schema) has the `decodeIfPresent` rule. Nothing reads `version` after decoding and a loaded file keeps its stored value, so a breaking change needs a branch on it in `init(from:)` as well as a new value in `Config.default` |
| Reset config | Quit Borma, then `rm ~/Library/Containers/com.ideamtrls.borma/Data/Library/Application\ Support/com.ideamtrls.borma/config.json`. The next launch writes defaults |
| Reset frecency state | Quit Borma, then `rm ~/Library/Containers/com.ideamtrls.borma/Data/Library/Application\ Support/com.ideamtrls.borma/frecency.json` |
| Reset the welcome bib in dev | Quit Borma, then `defaults delete com.ideamtrls.borma borma.welcome.dismissed`. `defaults` resolves that domain to the plist in the container. The next launch opens the panel with the bib |
| Surface a new log category | `Sources/App/Logging.swift` (add to `Log` enum), then `Log.<category>.error(...)` |
| Tune fuzzy-match scoring | `search.md` (`Matcher` constants table) |
| Upload a build to TestFlight | `Scripts/upload.sh`; `build.md` ("Uploading to TestFlight") has what it needs |
| View Borma's logs | `overview.md` (Logging), or filter by the `com.ideamtrls.borma` subsystem in Console.app |
| Wrap another FSEvents-style C API (callback + `info` pointer) | `concurrency.md` (`ContinuationBox` pattern) |

## Keeping this file current

This file has `globs: []`, so no source change routes here: when a source file is added, moved, or removed, update the reverse map in the same change. The `CLAUDE.md` router table is generated from each digest file's frontmatter, so change a row by editing that file's `scope` or `keywords`; `/digestmtrls:improve` audits the whole digest set and regenerates the table.

## See also

- `overview.md` — system map; the place to start when neither table above matches.
