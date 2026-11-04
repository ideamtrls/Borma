---
scope: Borma-specific vocabulary (frecency, welcome bib, conflict banner, ContinuationBox, two-name pattern)
globs: []
keywords: [glossary, terminology, vocabulary, frecency, welcome bib, conflict banner, two-name hotkey pattern, active vs saved shortcut, ContinuationBox, app scan vs app watcher vs config watcher]
updated: 2026-06-06
---

# Glossary

Borma-specific terminology. Each entry: what the term means, where the concept lives in code, and which doc owns the deep explanation. `CLAUDE.md` has a one-line stub for each; this file has the prose.

## Frecency

A score that combines launch *frequency* (how often) with *recency* (how recently) so apps you've been launching surface ahead of equally-named alternatives.

- Stored per `(bundleId, query)` pair in `frecency.json`.
- Half-life: 14 days. A launch contributes half its weight after that interval.
- Prefix match (the typed query is a prefix of a stored one) is damped by `0.7` so a single old long query doesn't dominate a short typed prefix.
- Source: `Sources/Search/FrecencyStore.swift`.
- Deep doc: `search.md`.

## Welcome bib

The one-time hotkey-hint footer that hangs off the bottom of the panel. Shows the current hotkey. Retires on the first panel dismiss.

- Storage: `UserDefaults` key `borma.welcome.dismissed`.
- Source: `Sources/App/WelcomeFlag.swift`; layout constants in `Sources/Panel/LayoutMetrics.swift` (`bibHeight`, `bibWidth`).
- Visibility: shown while `(welcomeActive || alwaysShowHint) && query.isEmpty`.
- Deep doc: `panel.md`.

## Conflict banner

The in-panel notice that appears when Spotlight owns ⌘Space and Borma has switched to its fallback. Includes a link that opens System Settings → Keyboard.

- Visibility: driven by `model.conflictActive` (set by `HotkeyController`).
- Source: `Sources/Panel/SearchView.swift` (rendering), `Sources/Hotkey/Hotkey.swift` (detection).
- Deep doc: `panel.md` (rendering), `hotkey.md` (mechanics).

## Two-name hotkey pattern

`KeyboardShortcuts` has no primitive to override a saved binding at runtime without overwriting the user's preference. Borma works around this by registering two `KeyboardShortcuts.Name` values:

- `.toggleBorma` — bound to the user's saved preference (visible in the Settings recorder).
- `.toggleBormaFallback` — runtime-only, no recorder, no UI surface.

Both invoke the same `onTrigger`. `evaluateBinding()` enables exactly one at a time. The user's saved preference is never overwritten.

- Source: `Sources/Hotkey/Hotkey.swift`.
- Deep doc: `hotkey.md`.

## Active vs. saved shortcut

The **saved** shortcut is what the user picked in Settings. The **active** shortcut (`HotkeyController.activeShortcut`) is what's actually registered with the system *right now*. They diverge during a Spotlight conflict: saved is ⌘Space, active is the ⌘⇧Space fallback.

UI strings that tell the user "press X to summon me" must use `activeShortcut`. UI strings that describe the user's stored preference (e.g. the recorder readout) must use the saved value.

- Source: `Sources/Hotkey/Hotkey.swift`.
- Deep doc: `hotkey.md`.

## ContinuationBox pattern

Pattern used by `FileWatcher` to bridge `FSEvents`' C callback into Swift's `AsyncStream` without leaving a dangling pointer.

The naive approach — `Unmanaged.passUnretained(self)` with `nil` retain/release on `FSEventStreamContext` — lets the FSEvents callback fire against a deallocated watcher. With the box, FSEvents holds a refcount on a small wrapper class that owns just the continuation, so the wrapper outlives the watcher long enough for any in-flight callback to complete safely.

If you wrap another FSEvents/Carbon-style API that takes an `info` pointer, follow this pattern.

- Source: `Sources/Config/FileWatcher.swift`.
- Deep doc: `concurrency.md`.

## App scan vs. app watcher vs. config watcher

Three related-but-distinct things to keep straight:

- **App scan** (`AppScanner.scan`) — one-shot walk of the configured search paths returning `[AppRecord]`. Runs off-main.
- **App watcher** — a `FileWatcher` over `config.searchPaths`. FSEvents over the *application* directories; fires whenever something there changes, prompting a rescan.
- **Config watcher** — a `FileWatcher` over the config file's *parent directory*. FSEvents over `~/Library/Application Support/com.ideamtrls.borma/`; fires when the config JSON is rewritten. On fire: reload config, rescan, *and replace the app watcher* (because `searchPaths` may have changed and the existing watcher is pointed at the old set).

- Source: `Sources/Search/Apps.swift`, `Sources/Config/FileWatcher.swift`, `Sources/App/AppDelegate.swift` (wiring).
- Deep doc: `overview.md` (data flow), `concurrency.md` (FileWatcher mechanics).
