---
scope: App discovery, fuzzy Matcher, FrecencyStore, LauncherModel ranking
globs: [Sources/Search/Apps.swift, Sources/Search/Matcher.swift, Sources/Search/FrecencyStore.swift, Sources/Search/LauncherModel.swift]
keywords: [fuzzy matching, frecency, AppScanner, AppLauncher, AppRecord, Matcher, scoring, LauncherModel, ranking, subsequence, greedy match, half-life, prefix match, pruning, rescan, search paths, two-pass walk, Safari symlink, app missing from results, Safari not appearing in list, frecency not boosting after launch, ranking feels wrong, frecency schema migration on load]
updated: 2026-11-03
---

# Search subsystem

App discovery, fuzzy matching, frecency, and the `LauncherModel` ranking that turn a query into a ranked list of `AppRecord`s.

## Where things live

- `AppRecord`, `AppLauncher.launch(_:)`, `AppScanner.scan(paths:)` (private `scanAsync`, `makeRecord`): `Sources/Search/Apps.swift`
- `Matcher.score(query:target:)`, the scoring constants, `fold`: `Sources/Search/Matcher.swift`
- `FrecencyStore` (`load`, `record`, `multiplier`, `prune`), `FrecencyData`, `FrecencyEntry`, `FrecencyDataV1`: `Sources/Search/FrecencyStore.swift`
- `LauncherModel` (`results`, `selectedApp(in:)`, `launchSelection`, `selectNext`, `selectPrev`, `reset`, `maxResults`): `Sources/Search/LauncherModel.swift`
- Wiring: `AppDelegate` (`frecency`, `model`, `rescan`, `startAppWatcher`, `startConfigWatcher`, `appSupportDir`): `Sources/App/AppDelegate.swift`
- Default search roots: `Config.default`, `Sources/Config/Config.swift`
- Readers of `results`: `SearchView`, `Sources/Panel/SearchView.swift`; `PanelController`, `Sources/Panel/Panel.swift`

## AppScanner

`AppScanner.scan(paths:)` is async: it runs the `nonisolated` `scanAsync` under `Task.detached(priority: .userInitiated)`, walks each root in order, and returns an `[AppRecord]`. There is no dedicated actor; `nonisolated` plus `Task.detached` is what keeps the walk off main.

**Roots and rescans.** Roots come from `config.searchPaths`, defaulting to `/Applications` and `/System/Applications` (`~/Applications` is not a default root). A root that is missing or isn't a directory is skipped, and one the sandbox can't read contributes no apps (`build.md`, "App sandbox at runtime"). `AppDelegate.rescan()` re-walks every root and replaces `model.apps` wholesale: at startup, on any app-watcher event, and on a config-directory event when `config.config` actually changed. The scanner logs nothing (`Log.scanner` exists but is unused), so a skipped root or a bad plist never reaches Console.

**Two-pass walk per root.** A flat `contentsOfDirectory(...)` pass with no options catches top-level `.app` entries, dropping names that start with `.` by hand. The recursive `enumerator(at:options: [.skipsHiddenFiles, .skipsPackageDescendants])` pass catches apps in subfolders; it doesn't descend into bundles, so an `.app` nested inside another `.app` is never found.

Safari is why the flat pass exists: `/Applications/Safari.app` is a symlink into the system cryptex and carries the `hidden` file flag, so the enumerator's `.skipsHiddenFiles` filters it out.

Don't add `.skipsHiddenFiles` to the flat pass — both passes would then miss Safari. A hidden-flagged `.app` in a subfolder is missed by both passes.

**Dedup.** By standardized file path, then by `CFBundleIdentifier` (if non-empty). The path dedup catches the same app appearing via both passes; the bundle-id dedup catches the same app installed in multiple locations. First seen wins, so root order decides which copy stays.

**Record fields.** `makeRecord` reads `Contents/Info.plist` directly, so names are the raw plist values with no localization. `displayName` is `CFBundleDisplayName`, then `CFBundleName`, then the file name; `fileName` is the bundle's file name without extension. A missing or unreadable plist still produces a record, with an empty `bundleId`. Empty-`bundleId` apps skip the bundle-id dedup, get no frecency (`record` no-ops, `multiplier` returns 1.0), and use the bundle path as `AppRecord.id`.

**Icon load hops to main.** `makeRecord` is `nonisolated`; the `NSWorkspace.shared.icon(forFile:)` call and the `AppRecord` construction inside it are wrapped in `MainActor.run`. The icon comes from the symlink-resolved path, while `bundleURL` keeps the unresolved path that launching uses. See `concurrency.md` for the rationale.

## AppLauncher

Single function: `AppLauncher.launch(_ app: AppRecord)`. Calls `NSWorkspace.shared.openApplication(at:configuration:)` with a default `NSWorkspace.OpenConfiguration()`. On failure the completion handler hops to main to log (`Log.app`) + `NSSound.beep()`.

## Matcher

Case- and diacritic-insensitive subsequence scoring — both strings are normalized via `folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)`, so "cafe" matches "Café". `Matcher.score(query:target:)` returns `Int?`; `nil` means the subsequence isn't present, and an empty query returns 0.

Constants (`Sources/Search/Matcher.swift`):

| Constant | Value | When |
|---|---|---|
| `exactMatchBonus` | 1000 | Folded `query == target`. Returned outright: the score is exactly 1000 and nothing below applies |
| `startBonus` | 100 | First matched char is at position 0 |
| `wordBoundaryBonus` | 50 | Matched char follows space, `-`, `_`, `.`, `/` (camelCase humps don't count) |
| `consecutiveBonus` | 15 | Matched char is adjacent to the previous match; stacks with `wordBoundaryBonus` |
| `gapPenalty` | 1 | Per character between non-adjacent matches; characters before the first match or after the last cost nothing |

The algorithm is a single left-to-right pass with `qi` advancing only on match. If `qi` reaches `q.count`, the accumulated score is returned; otherwise `nil`.

The pass is greedy: each query character takes its earliest remaining occurrence, with no backtracking. The bonuses reward word boundaries and tight runs only where the earliest occurrence lands on them, so `st` on "Visual Studio Code" scores -5 (`s` comes from "Visual") although "St" in "Studio" would earn 65. Target length isn't scored; it only breaks ties in `results`.

## FrecencyStore

Per-(bundleId, query) launch history with frequency × recency weighting. A plain `final class`, main-actor under default isolation, so `load()` and `save()` are synchronous disk I/O on main.

**File.** `frecency.json` in the directory from `appSupportDir()` (on-disk path: `overview.md`, "Persistence"). The config watcher covers the same directory, so every save wakes it.

**On-disk shape (v2):** `entries[bundleId][query] = FrecencyEntry`, where `FrecencyEntry = { launchCount: Int, lastLaunchedAt: TimeInterval }` (seconds since 1970). Nested keying lets `multiplier(...)` do O(queries-per-bundle) lookups instead of scanning every entry.

**Query keys.** `record` and `multiplier` key on `query.lowercased()`, with no trimming or diacritic folding, so "cafe" and "café" are separate history entries even though `Matcher` treats them alike.

**Migration.** Loading recognizes the v1 flat shape (`entries["<query>\u{1}<bundleId>"]`) and migrates to v2 in memory + persists; keys without the separator are dropped. See `FrecencyDataV1.migrated()`. Any other file (corrupt, or an unknown `version`) logs an error and starts empty with no backup, so the next `record` overwrites it.

**Pruning.** Only in `load()`, which runs once per process from `AppDelegate`'s `frecency` initializer. After a successful load (or migration), entries whose `lastLaunchedAt` is older than `pruneAge` (12 half-lives = 168 days ≈ 5.5 months) are dropped, along with bundles left with no queries, and the file is re-saved if anything was removed. At that age the recency factor is ~0.0002, so the multiplier contribution is negligible — pruning keeps the file and the per-keystroke lookup from growing without bound.

**Score formula:**

```
recency   = 0.5 ^ (age / halfLife)              # halfLife = 14 days, age floored at 0
frequency = ln(launchCount + 1) + 1.0           # diminishing returns
score     = 1.0 + frequency * recency           # always ≥ 1.0
```

A fresh single launch scores 2.69; a fresh entry with 100 launches scores 6.62. `launchCount` never decays and each entry has one `lastLaunchedAt`, so a single new launch restores a stale entry's whole count to full weight.

`multiplier(query:bundleId:)` returns the max of:

- 1.0 (also the whole result for an empty `bundleId` or a bundle with no history),
- the exact-query score, and
- the best score among other stored queries that *start with* the typed query, damped by `prefixMatchDamping = 0.7` (skipped for an empty query).

The damping prevents long historical queries from dominating short typed prefixes (e.g. you launched "saf" → Safari once a month ago, but you type "s" today: 0.7 × 1.38 = 0.97, so the 1.0 floor wins and there is no boost).

Matching is one-way. Stored "saf" can boost typed "s" and "sa", but typed "safa" gets nothing from it, so a launch only helps the exact text typed and its prefixes.

`record(query:bundleId:)` increments the count, updates the timestamp, and saves atomically. It no-ops on an empty `bundleId`.

## LauncherModel

`@Observable`. Source of truth for the active search session:

- `apps: [AppRecord]` — current scan result
- `query: String` — text the user is typing; any edit clears `selection`, returning the highlight to the top result
- `selection: AppRecord.ID?` — the row the user moved to, held by identity so a rescan can't slide it onto another app. `nil` means the top result. `selectedApp(in:)` resolves it against `results` and falls back to the top result if that app has gone. `selectNext` and `selectPrev` stop at the first and last rows with no wrap; a row tap in `SearchView` assigns it directly
- `conflictActive`, `activeHotkey` — UX flags pushed by `AppDelegate` from `HotkeyController`'s `onBindingChanged`
- `welcomeActive` — UX flag pushed by `PanelController` from `WelcomeFlag`
- `onLaunch`, `onDismissRequested` — callbacks (`@ObservationIgnored`)

`reset()` clears `query` and `selection`; `PanelController` calls it from `show()` and `hide()`.

`results` is a computed property — the ranking happens on every read, with no caching, and an empty query returns `[]`. `SearchView` and `PanelController` read it several times per render, and callers that use it more than once hold it in a local. Each app is scored against both its `displayName` and its on-disk `fileName` (the `.app` name without extension, skipped when identical), keeping the better match — this is what lets "vscode" find "Visual Studio Code" whose display name is just "Code". The candidate's final score is `max(matchScore, 1) × frecencyMultiplier` — the floor matters because gap penalties can drive the match score negative, and multiplying a negative base by a frecency boost would rank an app worse the more it's launched. Sort key: `score desc, displayName.count asc, displayName alpha asc` (`localizedCaseInsensitiveCompare`). Capped at `maxResults = 8`.

`launchSelection()` invokes `onLaunch` (with the selected record and current query), then `onDismissRequested`; with no results it only dismisses. `AppDelegate` wires `onLaunch` in its lazy `model` initializer (record frecency, then open the app) and `onDismissRequested` in `applicationDidFinishLaunching` (`PanelController.hide()`), so a launch records frecency, opens the app, and hides the panel in one shot.

## See also

- `concurrency.md` — `-default-isolation MainActor`, why the scan is `nonisolated` and hops to main for icons
- `panel.md` — `PanelController` resizes the panel from `results.count`
