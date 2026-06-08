# Borma

macOS app launcher with a global-hotkey-summoned floating search panel.

Rules that apply to *every* task (area-specific conventions live in the memory files, loaded on demand):

- **Logging:** Use `Log.<category>` from `Sources/App/Logging.swift`; never `print()`. Add `privacy: .public` to interpolated values you intend to surface in Console.
- **Doc updates:** When you change behavior, update the matching `Memory/` file as part of the same change. Run `/memorymtrls:update` at the end of a session to refresh docs whose covered source changed.

<!-- memorymtrls:start -->

`.notes/` should be used for **personal workflow scratch** and gitignored. Place artifacts produced while working in here, such as plans, specs, exploratory writeups, eg thinking out loud.

- Plans → `.notes/plans/YYYY-MM-DD-<slug>.md` — execution outlines for multi-step work. Stay as historical record after the work lands.
- Specs → `.notes/specs/YYYY-MM-DD-<slug>.md` — designs before implementation. After landing, fold architectural takeaways into the relevant `Memory/` file.
- Other → `.notes/scratch/`.

## Memory

This project's working context lives in `Memory/`, with one file per category of context. The table below maps task level concerns to the context file(s) that cover it.

**IMPORTANT: Before starting a task, scan this table. If any rows match the task, read the relevant memory files, and then start the task.** Read only the rows that match. Context window efficiency is gained by not reading irrelevant context; if nothing matches, proceed without reading any.

| Memory file | Read this when… |
| ----------- | --------------- |
| `Memory/overview.md` | getting oriented; locating where something is defined, what runs at startup, where config/frecency live on disk, or how the dismiss flow works |
| `Memory/build.md` | regenerating the Xcode project, changing `project.yml` or `Borma.entitlements`, adding an SPM dependency, or fixing signing / sandbox / CI build issues |
| `Memory/concurrency.md` | touching async / isolation code, hitting a `Sendable` or data-race error, writing an FSEvents wrapper, or chasing an FSEvents-callback / `dispatch_assert_queue` crash |
| `Memory/search.md` | working on app discovery, fuzzy-match scoring, frecency ranking, or an "app missing from results" / "ranking feels wrong" bug |
| `Memory/panel.md` | changing panel sizing / position / dismissal, the welcome bib, or the conflict banner — or a "panel resizes / dismisses wrong" bug |
| `Memory/hotkey.md` | working on the global hotkey, diagnosing "hotkey not firing", or the Spotlight ⌘Space conflict + fallback |
| `Memory/glossary.md` | you hit Borma-specific jargon (frecency, welcome bib, conflict banner, two-name pattern, ContinuationBox) and need the definition |
| `Memory/index.md` | you can't find the right doc from this table, or need the source→doc reverse map, doc sizes, or the full task index |

<!-- memorymtrls:end -->
