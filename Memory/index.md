---
scope: Deep index — source→doc reverse map, doc sizes, full task index
globs: []
keywords: [index, navigation, quickstart, reverse map, source to doc, doc sizes, task index, can't find the right doc, which doc covers this file]
updated: 2026-06-10
---

# Memory index

The deep index. `CLAUDE.md` carries the quick version (the generated router table, plus conventions). This file adds: a reverse map (source file → which docs cover it), doc sizes for context budgeting, and the full glossary pointer.

If you're loading docs into context: read `CLAUDE.md` first (always loaded anyway), come here only when you need the reverse map or a doc you can't locate from the router table.

## Quickstart for a fresh agent

1. **Read `overview.md`** for the system map.
2. **Skim `glossary.md`** for Borma-specific vocabulary (frecency, bib, conflict banner, two-name pattern, ContinuationBox, etc.).
3. **Read the topic-specific doc** for what you're touching — see "By topic" below or in `CLAUDE.md`.
4. **Apply Conventions** from `CLAUDE.md` before writing code.
5. **If your task isn't on either table**, fall back to the reverse map below to find the right doc from the source file you're editing.

## By topic

Every memory file is small enough to read in full — pick the topic, open that file, and don't bother budgeting by length.

| Topic | File |
| --- | --- |
| System map, source layout, component graph, data flow, persistence | `overview.md` |
| xcodegen, project regeneration, dev loop, asset catalog | `build.md` |
| Swift 6 isolation, AppKit hopping, FSEvents `ContinuationBox` pattern | `concurrency.md` |
| App discovery, fuzzy matching, frecency | `search.md` |
| NSPanel configuration, window behavior, welcome flag | `panel.md` |
| Global hotkey, Spotlight conflict fallback | `hotkey.md` |
| Borma-specific terminology | `glossary.md` |

## By source file (reverse map)

When you're editing a specific source file, look here for which docs cover it.

| Source file | Primary doc | Also covered in |
| --- | --- | --- |
| `Sources/App/BormaApp.swift` | `overview.md` (Scenes, MenuBarExtra, Settings) | `hotkey.md` (Recorder→`refreshHotkeyBinding`) |
| `Sources/App/AppDelegate.swift` | `overview.md` (component graph, data flow) | `search.md` (model wiring), `concurrency.md` (rescan dispatch) |
| `Sources/App/Logging.swift` | — | `CLAUDE.md` Conventions ("use `Log.<category>`"); subsystem from `AppInfo` |
| `Sources/App/AppInfo.swift` | `overview.md` (bundle identity; backs log subsystem + App Support dir) | — |
| `Sources/App/WelcomeFlag.swift` | `panel.md` (welcome bib retire-on-hide) | `glossary.md` |
| `Sources/Panel/Panel.swift` | `panel.md` (NSPanel, sizing, Settings adoption) | `concurrency.md` (observation re-arm) |
| `Sources/Panel/SearchView.swift` | `panel.md` (rendering, hotkey formatting) | `hotkey.md` (conflict banner) |
| `Sources/Panel/LayoutMetrics.swift` | `panel.md` (sizing) | `concurrency.md` (`nonisolated` for `Shape`) |
| `Sources/Config/Config.swift` | `overview.md` (persistence shape) | — |
| `Sources/Config/ConfigStore.swift` | `overview.md` (persistence) | `panel.md` (Settings binding) |
| `Sources/Config/FileWatcher.swift` | `concurrency.md` (`ContinuationBox`) | `overview.md` (data flow), `glossary.md` |
| `Sources/Search/Apps.swift` | `search.md` (`AppScanner`, `AppLauncher`) | `concurrency.md` (off-main scan, `Sendable`) |
| `Sources/Search/Matcher.swift` | `search.md` (scoring constants) | — |
| `Sources/Search/FrecencyStore.swift` | `search.md` (formula, migration) | `glossary.md` |
| `Sources/Search/LauncherModel.swift` | `search.md` (orchestrator) | `panel.md` (observation surface) |
| `Sources/Hotkey/Hotkey.swift` | `hotkey.md` (controller, Spotlight detection) | `glossary.md` (two-name pattern, active vs. saved) |
| `project.yml` | `build.md` (xcodegen) | — |
| `Borma.entitlements` | `build.md` (app sandbox, signing) | — |

## Task index (full)

Situations mapped to the doc(s) to read. Richer than the router's coarse "read when" rows.

| When you want to… | Read |
| --- | --- |
| Add a new persisted user setting | `overview.md` (persistence), `Sources/Config/Config.swift`, `BormaApp.swift` (Settings scene) |
| Add a new SwiftUI view inside the panel | `panel.md` (NSHostingView, observation re-arm) |
| Add a new toggle to Settings | `BormaApp.swift` (SettingsView), `Sources/Config/Config.swift` (Config struct + `init(from:)` migration) |
| Adopt a new external SPM dependency | `build.md` (project.yml packages), then `xcodegen generate` |
| Change panel sizing or positioning | `panel.md`, `concurrency.md` (`Shape` isolation) |
| Diagnose a hotkey-not-firing bug | `hotkey.md` (conflict + fallback) |
| Force a Spotlight conflict in dev | System Settings → Keyboard → Keyboard Shortcuts → Spotlight → restore ⌘Space |
| Migrate the frecency on-disk schema | `search.md` (`FrecencyStore` migration); model the v1→v2 example in `FrecencyDataV1.migrated()` |
| Migrate the config on-disk schema | `Sources/Config/Config.swift` (`init(from:)` already does forward-compatible decoding via `decodeIfPresent`); bump `version` if shape changes |
| Reset frecency state | `rm ~/Library/Application\ Support/com.ideamtrls.borma/frecency.json` |
| Reset the welcome bib in dev | `defaults delete com.ideamtrls.borma borma.welcome.dismissed` |
| Surface a new log category | `Sources/App/Logging.swift` (add to `Log` enum), then `Log.<category>.error(...)` |
| Tune fuzzy-match scoring | `search.md` (`Matcher` constants table) |
| Wrap another FSEvents/Carbon API | `concurrency.md` (`ContinuationBox` pattern) |

## Conventions

See `CLAUDE.md`'s **Conventions** section. Always loaded into context — there's no point duplicating here.

## Glossary

See `glossary.md`.

## Keeping docs current

Memory files are updated inline, as part of any change that alters how an area works (see the maintenance instruction in `CLAUDE.md`): edit the file whose `globs:` cover the changed source and bump its `updated`. Run `/memorymtrls:improve` periodically to audit the whole set — it enforces the format spec, rewrites stale claims against the current source, and regenerates the router.
