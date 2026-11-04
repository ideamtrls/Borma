# Borma

macOS app launcher with a global-hotkey-summoned floating search panel.

Rules that apply to *every* task (area-specific conventions live in the digest files, loaded on demand):

- **Logging:** Use `Log.<category>` from `Sources/App/Logging.swift`; never `print()`. Add `privacy: .public` to interpolated values you intend to surface in Console.
- **Doc updates:** When you change behavior, update the matching `Digest/` file as part of the same change. Run `/digestmtrls:improve` periodically to audit the whole digest set.

<!-- digestmtrls:start -->

## Digest

This project's working context lives in `Digest/`, with one file per category of context. The table below maps task level concerns to the context file(s) that cover it.

**IMPORTANT: Before starting a task, scan this table. If any rows match the task, read the relevant digest files, and then start the task. If you're unsure about a row, read only the first 6 lines of its file, the frontmatter, and decide from those.** Read only the rows that match. Context window efficiency is gained by not reading irrelevant context; if nothing matches, proceed without reading any.

**IMPORTANT: Before finishing a task that changed how an area works or where its code lives, update that area's digest file.** Keep edits surgical and bump `updated`. Digest files describe the current state of the system — what *is*, never what *was*. Do not narrate the change ("previously", "no longer", "moved from…"); rewrite the affected text as if the current state had always been true. If the work created a new area with no matching file, tell the user rather than inventing a category.

| Digest file | Read this when… |
| ----------- | --------------- |
| `Digest/overview.md` | getting oriented; locating where something is defined, what runs at startup, the config schema, logging, where config/frecency/UserDefaults live on disk, or a "config edit has no effect" / "config reset to defaults" problem |
| `Digest/build.md` | regenerating the Xcode project, changing `project.yml` or `Borma.entitlements`, adding an SPM dependency or source file, bumping the version, a blank app icon, how the app sandbox changes runtime behavior, or fixing signing / CI build issues |
| `Digest/concurrency.md` | touching async / isolation code, hitting a `Sendable`, `nonisolated`, or data-race error, adding a custom `Shape`, writing an FSEvents wrapper, or chasing an FSEvents-callback / `dispatch_assert_queue` crash |
| `Digest/search.md` | working on app discovery, fuzzy-match scoring, frecency ranking, or an "app missing from results" / "ranking feels wrong" bug |
| `Digest/panel.md` | changing the search view, panel sizing / position / dismissal, Settings adoption, the welcome bib, or the conflict banner — or a "panel resizes / dismisses wrong" bug |
| `Digest/hotkey.md` | working on the global hotkey, diagnosing "hotkey not firing" or "conflict banner never shows", or the Spotlight ⌘Space conflict + fallback |
| `Digest/glossary.md` | you hit Borma-specific jargon (frecency, welcome bib, conflict banner, two-name pattern, ContinuationBox) and need the definition |
| `Digest/index.md` | you can't find the right file from this table, need the source→digest reverse map, or want a dev command (reset frecency / config / welcome bib, force a Spotlight conflict) or a schema-change recipe |
| `Digest/notes.md` | writing a plan, spec, or scratch notes (these go in `.notes/`, which is gitignored) |

<!-- digestmtrls:end -->
