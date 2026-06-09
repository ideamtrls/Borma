---
scope: App discovery, fuzzy Matcher, FrecencyStore, LauncherModel ranking
globs:
  - Sources/Search/Apps.swift
  - Sources/Search/Matcher.swift
  - Sources/Search/FrecencyStore.swift
  - Sources/Search/LauncherModel.swift
keywords: [fuzzy matching, frecency, AppScanner, AppLauncher, Matcher, scoring, LauncherModel, ranking, subsequence, half-life, prefix match, two-pass walk, Safari symlink, app missing from results, Safari not appearing in list, frecency not boosting after launch, ranking feels wrong, frecency schema migration on load]
updated: 2026-06-09
---

# Search subsystem

`Sources/Search/` contains the pieces that turn a query into a ranked list of `AppRecord`s:

- `Apps.swift`            — `AppRecord`, `AppScanner`, `AppLauncher`
- `Matcher.swift`         — fuzzy subsequence scoring
- `FrecencyStore.swift`   — per-(bundleId, query) launch history with decay
- `LauncherModel.swift`   — Observable orchestrator

## AppScanner

`AppScanner.scan(paths:)` is async; it dispatches to a background actor via `Task.detached`, walks each configured root, and returns an `[AppRecord]`.

**Two-pass walk per root.** A flat `contentsOfDirectory(...)` pass catches top-level `.app` entries (notably Safari, which is a symlink into the system cryptex and is invisible to the recursive enumerator). The recursive `enumerator(at:options: [.skipsHiddenFiles, .skipsPackageDescendants])` pass catches everything else.

Don't add `.skipsHiddenFiles` to the flat pass — Safari's symlink carries the hidden flag and would be filtered out.

**Dedup.** By standardized file path, then by `CFBundleIdentifier` (if non-empty). The path dedup catches the same app appearing via both passes; the bundle-id dedup catches the same app installed in multiple locations.

**Icon load hops to main.** `makeRecord` runs on the background actor; the `NSWorkspace.shared.icon(forFile:)` call inside it is wrapped in `MainActor.run`. See `concurrency.md` for the rationale.

## AppLauncher

Single function: `AppLauncher.launch(_ app: AppRecord)`. Calls `NSWorkspace.shared.openApplication(at:configuration: .init())`. On failure: log + `NSSound.beep()`.

## Matcher

Case- and diacritic-insensitive subsequence scoring — both strings are normalized via `folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)`, so "cafe" matches "Café". `Matcher.score(query:target:)` returns `Int?`; `nil` means the subsequence isn't present.

Constants (`Sources/Search/Matcher.swift`):

| Constant | Value | When |
|---|---|---|
| `exactMatchBonus` | 1000 | `query == target` case-insensitively |
| `startBonus` | 100 | First matched char is at position 0 |
| `wordBoundaryBonus` | 50 | Matched char follows space, `-`, `_`, `.`, `/` |
| `consecutiveBonus` | 15 | Matched char is adjacent to the previous match |
| `gapPenalty` | 1 | Per character between non-adjacent matches |

The algorithm is a single left-to-right pass with `qi` advancing only on match. If `qi` reaches `q.count`, the accumulated score is returned; otherwise `nil`.

Bias is toward word-boundary matches and tight runs. Tune by editing the constants.

## FrecencyStore

Per-(bundleId, query) launch history with frequency × recency weighting.

**On-disk shape (v2):** `entries[bundleId][query] = FrecencyEntry`, where `FrecencyEntry = { launchCount: Int, lastLaunchedAt: TimeInterval }`. Nested keying lets `multiplier(...)` do O(queries-per-bundle) lookups instead of scanning every entry.

**Migration.** Loading recognizes the v1 flat shape (`entries["<query>\u{1}<bundleId>"]`) and migrates to v2 in memory + persists. See `FrecencyDataV1.migrated()`.

**Score formula:**

```
recency   = 0.5 ^ (age / halfLife)              # halfLife = 14 days
frequency = log(launchCount + 1) + 1.0          # diminishing returns
score     = 1.0 + frequency * recency           # always ≥ 1.0
```

`multiplier(query:bundleId:)` returns the max of:

- the exact-query score, and
- the best score among stored queries that *start with* the typed query, damped by `prefixMatchDamping = 0.7`.

The damping prevents long historical queries from dominating short typed prefixes (e.g. you launched "saf" → Safari once a month ago, but you type "s" today).

`record(query:bundleId:)` increments the count, updates the timestamp, and saves atomically.

## LauncherModel

`@Observable`. Source of truth for the active search session:

- `apps: [AppRecord]` — current scan result
- `query: String` — text the user is typing; any edit resets `selection` to 0 (the results list changes underneath, so a stale index would point at the wrong app)
- `selection: Int` — index into `results` (clamped 0…count-1)
- `welcomeActive`, `conflictActive`, `activeHotkey` — UX flags pushed by `AppDelegate` from `HotkeyController` and `WelcomeFlag`
- `onLaunch`, `onDismissRequested` — callbacks (`@ObservationIgnored`)

`results` is a computed property — the ranking happens on every read. Each app is scored against both its `displayName` and its on-disk `fileName` (the `.app` name without extension, skipped when identical), keeping the better match — this is what lets "vscode" find "Visual Studio Code" whose display name is just "Code". The candidate's final score is `max(matchScore, 1) × frecencyMultiplier` — the floor matters because gap penalties can drive the match score negative, and multiplying a negative base by a frecency boost would rank an app worse the more it's launched. Sort key: `score desc, displayName.count asc, displayName alpha asc`. Capped at `maxResults = 8`.

`launchSelection()` invokes `onLaunch` (with the selected record and current query), then `onDismissRequested`. `AppDelegate` wires these in `applicationDidFinishLaunching` so a launch records frecency, opens the app, and hides the panel in one shot.
