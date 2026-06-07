# Borma

macOS app launcher with a global-hotkey-summoned floating search panel.

<!-- memorymtrls:start -->
## Memory

This project's working context lives in `Memory/`, with one file per category of context. The table below maps task level concerns to the context file(s) that cover it.

**IMPORTANT: Before starting a task, scan this table. If any rows match the task, read the relevant memory files, and then start the task.** Read only the rows that match. Context window efficiency is gained by not reading irrelevant context; if nothing matches, proceed without reading any.

| Memory file | Read this when… |
| ----------- | --------------- |
| `Memory/overview.md` | getting oriented; locating where something is defined, what runs at startup, where config/frecency live on disk, or how the dismiss flow works |
| `Memory/build.md` | regenerating the Xcode project, changing `project.yml`, adding an SPM dependency, or fixing signing / CI build issues |
| `Memory/concurrency.md` | touching async / isolation code, hitting a `Sendable` or data-race error, writing an FSEvents wrapper, or chasing an FSEvents-callback / `dispatch_assert_queue` crash |
| `Memory/search.md` | working on app discovery, fuzzy-match scoring, frecency ranking, or an "app missing from results" / "ranking feels wrong" bug |
| `Memory/panel.md` | changing panel sizing / position / dismissal, the welcome bib, or the conflict banner — or a "panel resizes / dismisses wrong" bug |
| `Memory/hotkey.md` | working on the global hotkey, diagnosing "hotkey not firing", or the Spotlight ⌘Space conflict + fallback |
| `Memory/glossary.md` | you hit Borma-specific jargon (frecency, welcome bib, conflict banner, two-name pattern, ContinuationBox) and need the definition |
| `Memory/index.md` | you can't find the right doc from this table, or need the source→doc reverse map, doc sizes, or the full task index |
<!-- memorymtrls:end -->

## Conventions

Rules that should hold for every edit. When in doubt, follow these before reaching for the docs.

- **Project file:** Never edit `Borma.xcodeproj/` by hand. Change `project.yml` and re-run `xcodegen generate`.
- **Isolation:** Swift 6 with `-default-isolation MainActor`. Don't add redundant `@MainActor`. Mark `nonisolated` only when crossing to a background actor or to a SwiftUI `Shape` (which runs off-main).
- **Logging:** Use `Log.<category>` from `Sources/App/Logging.swift`. Never `print()`. Add `privacy: .public` to interpolated values you intend to surface in Console.
- **Persistence:** JSON under `~/Library/Application Support/com.ideamtrls.borma/`. Always atomic writes (`Data.write(to:options: .atomic)`). `Codable` with an explicit `version` field. Provide a migration when bumping it.
- **File watching:** Watch the *directory*, not the file — atomic writes replace the inode and a file-level watch would miss the replacement. For any new FSEvents wrapper, follow the `ContinuationBox` pattern.
- **Sendable:** `@unchecked Sendable` requires the "assembled on main, then immutable" contract. Justify the use with a comment when it isn't obvious.
- **Pixel constants:** Live in a `nonisolated enum` (see `LauncherDimensions`) so SwiftUI `Shape.path(in:)` can read them off-main.
- **Observation:** Use `@ObservationIgnored` for closure properties on `@Observable` types so reassigning them doesn't trigger a re-render. Re-arm `withObservationTracking` from inside its own `onChange` closure if you need it to keep firing.
- **Doc updates:** When you change behavior, update the matching `Memory/` file in the same commit. Each doc carries `scope:`, `globs:`, and `keywords:` in its YAML front matter — grep these to locate the right doc by symptom or by source path. Run `/memorymtrls:update` at the end of a session to refresh docs whose covered source changed.

## Workflow

`Memory/` is the **living memory** of how the system works. Update the relevant file when behavior changes substantively. Add new topic files for new concerns rather than bloating existing ones.

`.notes/` is **personal workflow scratch** (gitignored). Place artifacts produced while working — plans, specs, exploratory writeups — here:

- Plans → `.notes/plans/YYYY-MM-DD-<slug>.md` — execution outlines for multi-step work. Stay as historical record after the work lands.
- Specs → `.notes/specs/YYYY-MM-DD-<slug>.md` — designs before implementation. After landing, fold architectural takeaways into the relevant `Memory/` file.
- Other → `.notes/scratch/`.
