---
scope: Borma-specific vocabulary (frecency, welcome bib, dismiss, conflict banner, two-name pattern, active vs. saved shortcut, ContinuationBox, app vs. config watcher)
globs: []
keywords: [glossary, terminology, vocabulary, jargon, frecency, welcome bib, hint, footer, dismiss, conflict banner, two-name hotkey pattern, active vs saved shortcut, activeShortcut, activeHotkey, ContinuationBox, app scan vs app watcher vs config watcher, two-pass walk, input section, LauncherSurface, Settings adoption, observation re-arm]
updated: 2026-11-03
---

# Glossary

Borma-specific vocabulary: what each term means, where it lives in code, and which digest file owns the detail.

## Frecency

A launch-history score combining *frequency* and *recency*, stored per `(bundleId, query)`. `FrecencyStore.multiplier(query:bundleId:)` multiplies the match score in `LauncherModel.results` and is never below 1.0, so frecency only helps.

- Source: `Sources/Search/FrecencyStore.swift`.
- Deep doc: `search.md`.

## Welcome bib

The hotkey-hint footer hanging off the bottom of the panel, showing the active hotkey. It appears until the first dismiss, or on every open while Settings' "Always show hotkey" (`alwaysShowHint`) is on. Code also calls it the "hint" or "footer" (`shouldShowHint`, `footerHintLine`).

- Source: `Sources/App/WelcomeFlag.swift`, `Sources/Panel/SearchView.swift`.
- Deep doc: `panel.md`.

## Dismiss

`PanelController.hide()`: orders the panel out, resets the query, and retires the welcome flag if it's still active. Click-away is not a dismiss.

- Source: `Sources/Panel/Panel.swift`.
- Deep doc: `panel.md`.

## Conflict banner

The in-panel notice that Spotlight owns ⌘Space and Borma has switched to its fallback, rendered while `model.conflictActive`. Sandboxed builds never reach it, because conflict detection can't read the Spotlight plist there.

- Source: `Sources/Panel/SearchView.swift` (rendering), `Sources/Hotkey/Hotkey.swift` (detection).
- Deep doc: `hotkey.md` (mechanics), `panel.md` (rendering).

## Two-name hotkey pattern

Two `KeyboardShortcuts.Name` values, because the library can't override a binding at runtime without overwriting the saved preference: `.toggleBorma` holds the user's saved shortcut and `.toggleBormaFallback` holds the fallback. `evaluateBinding()` keeps one enabled at a time.

- Source: `Sources/Hotkey/Hotkey.swift`.
- Deep doc: `hotkey.md`.

## Active vs. saved shortcut

The **saved** shortcut is what the user picked in Settings, or the ⌘⇧Space default. The **active** shortcut (`HotkeyController.activeShortcut`, surfaced to views as `model.activeHotkey`) is what's registered with the system. They diverge only on the fallback: saved ⌘Space, active ⌘⇧Space.

- Source: `Sources/Hotkey/Hotkey.swift`.
- Deep doc: `hotkey.md`.

## ContinuationBox pattern

A small class that owns the `AsyncStream.Continuation` for `FileWatcher`. FSEvents holds a refcount on the box rather than on the watcher, so an in-flight callback can't dereference a deallocated `FileWatcher`.

- Source: `Sources/Config/FileWatcher.swift`.
- Deep doc: `concurrency.md`.

## App scan vs. app watcher vs. config watcher

Three related-but-distinct things to keep straight:

- **App scan** (`AppScanner.scan(paths:)`) — one-shot walk of `config.searchPaths` returning `[AppRecord]`.
- **App watcher** — a `FileWatcher` over `config.searchPaths`. Any change there prompts a rescan.
- **Config watcher** — a `FileWatcher` over the config file's *parent directory*, so it fires on every write there, frecency saves included. It rescans and replaces the app watcher only when the reloaded `Config` differs.

- Source: `Sources/Search/Apps.swift`, `Sources/Config/FileWatcher.swift`, `Sources/App/AppDelegate.swift` (wiring).
- Deep doc: `overview.md` (data flow), `concurrency.md` (`FileWatcher` mechanics), `search.md` (`AppScanner`).

## Two-pass walk

How `AppScanner` discovers apps in each root: a flat `contentsOfDirectory` pass, which catches Safari's hidden-flagged symlink, then a recursive `enumerator` pass for everything else.

- Source: `Sources/Search/Apps.swift`.
- Deep doc: `search.md`.

## Input section and launcher surface

- **Input section** — the search field, result rows, and conflict banner, excluding the welcome bib.
- **`LauncherSurface`** — the private `Shape` that draws the panel's silhouette, joining the input section and the narrower bib with two concave fillets.

- Source: `Sources/Panel/LayoutMetrics.swift`, `Sources/Panel/SearchView.swift`.
- Deep doc: `panel.md` (sizing), `concurrency.md` (why `LauncherSurface` is `nonisolated`).

## Settings adoption

When another window of the app takes key from the panel (in practice the Settings window), `PanelController` stores it as `settingsWindow` and returns focus to the search field when it closes.

- Source: `Sources/Panel/Panel.swift`.
- Deep doc: `panel.md`.

## Observation re-arm

`withObservationTracking` fires its `onChange` only once, so `PanelController.observeResults()` re-installs itself after each resize.

- Source: `Sources/Panel/Panel.swift`.
- Deep doc: `panel.md`.
