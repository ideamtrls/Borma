---
scope: Swift 6 -default-isolation MainActor model, what runs off main and how it hops back, Sendable rules, FSEvents ContinuationBox, nonisolated Shapes
globs: [Sources/Config/FileWatcher.swift, Sources/Panel/LayoutMetrics.swift, Sources/Panel/SearchView.swift, Sources/Search/Apps.swift]
keywords: [MainActor, default-isolation, Sendable, unchecked Sendable, nonisolated, nonisolated(unsafe), deinit isolation, AsyncStream, FSEvents, ContinuationBox, directory watch, atomic write, Task.detached, MainActor.run, Task @MainActor hop, rescan overlap, Shape, observation, withObservationTracking onChange, DirectoryEnumerator, Sendable warning or error, data race, FSEvents callback after dealloc, EXC_BREAKPOINT in _FSEventStreamDeallocate, dispatch_assert_queue trap on utility-qos, Shape cannot read main-actor constant, main actor-isolated default value in a nonisolated context, Shape conformance crosses into main actor-isolated code, Log referenced from a nonisolated context, DirectoryEnumerator makeIterator unavailable from async]
updated: 2026-11-03
---

# Concurrency

Swift 6 `-default-isolation MainActor` model: what runs off main and how it hops back, `Sendable` rules, the FSEvents `ContinuationBox`, and `nonisolated` `Shape`s.

## Where things live
- Isolation flag: `project.yml`, `OTHER_SWIFT_FLAGS` and `SWIFT_VERSION`
- Off-main app scan: `Sources/Search/Apps.swift`, `AppScanner.scan(paths:)`, `scanAsync(paths:)`, `makeRecord(bundleURL:)`
- The only `@unchecked Sendable`: `Sources/Search/Apps.swift`, `AppRecord`
- Hop out of a `@Sendable` completion handler: `Sources/Search/Apps.swift`, `AppLauncher.launch(_:)`
- FSEvents wrapper: `Sources/Config/FileWatcher.swift`, `FileWatcher`, `FileWatcher.ContinuationBox`, `fileWatcherRetain`, `fileWatcherRelease`, `fileWatcherCallback`
- Watcher consumers and rescans: `Sources/App/AppDelegate.swift`, `startConfigWatcher()`, `startAppWatcher()`, `rescan()`
- `nonisolated` shape: `Sources/Panel/SearchView.swift`, `LauncherSurface`
- `nonisolated` constants: `Sources/Panel/LayoutMetrics.swift`, `LauncherDimensions`
- Observation re-arm: `Sources/Panel/Panel.swift`, `PanelController.observeResults()`
- `@Observable` models: `Sources/Search/LauncherModel.swift`, `LauncherModel`; `Sources/Config/ConfigStore.swift`, `ConfigStore`

## What "default-isolation MainActor" means

Borma builds in Swift 6 language mode with `-default-isolation MainActor` set in `project.yml`. Every declaration is implicitly `@MainActor` unless explicitly marked otherwise.

- Top-level functions, types, properties, and methods are `@MainActor` without needing the attribute.
- Adding `@MainActor` to a declaration that's already inside main-actor isolation is redundant. **Don't.** A closure inside a `@Sendable` callback is not inside that isolation, so it does need the attribute (see the hop forms below).
- To opt out, mark with `nonisolated`. Conforming to `Sendable` does not opt out: `FileWatcher`, `FileWatcher.ContinuationBox`, and `AppRecord` are all still main-actor types. Borma declares no custom actors.
- A plain `deinit` is nonisolated even on a main-actor class, so it can't call main-actor methods or read main-actor `static let`s.
- Nonisolated code can read instance `let`s of `Sendable` type on a main-actor type (`box.continuation` in `fileWatcherCallback`, `record.bundleId` in `scanAsync`), but not its computed properties (`AppRecord.id`), methods, or `static let`s.
- `Log` is at default isolation, so `Log.<category>` is a compile error from nonisolated code: `scanAsync`, the FSEvents callbacks, any `deinit`. Log after a hop, as `AppLauncher.launch(_:)` does.

Example: `AppScanner`'s scan methods (`scanAsync`, `makeRecord`) are explicitly `nonisolated` so the directory walk runs off-main under `Task.detached`. `Matcher`, by contrast, is a pure utility that happens to run *on* main — it's only ever called from `LauncherModel.results`, a main-actor computed property — so it's left at default isolation. Being a pure function doesn't require `nonisolated`; needing to run off-main does.

## What runs off main

Everything not listed here runs on main, including `Matcher` scoring and the synchronous file I/O in `ConfigStore` and `FrecencyStore`.

- **App scan:** `AppScanner.scan(paths:)` runs `scanAsync` in `Task.detached(priority: .userInitiated)`. It walks serially and hops to main once per candidate bundle for the icon.
- **FSEvents callbacks:** `fileWatcherRetain`, `fileWatcherRelease`, and `fileWatcherCallback`.
- **`LauncherSurface.path(in:)`:** SwiftUI calls it off the main actor.
- **`@Sendable` callbacks:** the `openApplication` completion handler in `AppLauncher.launch(_:)` and the `onChange` closure in `PanelController.observeResults()`, and the `didActivateApplicationNotification` observer in `HotkeyController` are nonisolated. Each only hops back to main.

A bare `Task { }` in main-actor code inherits main. That covers `AppDelegate`'s initial `rescan()` and its watcher loops, `HotkeyController.settingsWatch`, and `PanelController.panelResignedKey`, which uses one to defer a run-loop turn.

`rescan()` has no cancellation or generation guard. It reads `config.searchPaths`, then awaits the scan, so scans from startup, the config loop, and the app loop can overlap, and whichever finishes last sets `model.apps`.

## AppKit stays on main

Only part of AppKit is annotated. `NSPanel`/`NSWindow` (through `NSResponder`) and `NSApp` are `@MainActor` in the SDK, and off-main use gets a warning, not an error, even in Swift 6 mode. `NSWorkspace`, `NSScreen`, and `NSImage` have no actor annotation, so off-main calls compile silently. Borma treats all of them as main-only by convention, so a clean build doesn't show an AppKit call is in the right place.

**Stay on main.** If the work is fast, just call directly — the default isolation puts you on main anyway.

**Hop back to main for the AppKit call.** In an `async` function, wrap the call in `MainActor.run`:

```swift
nonisolated private static func makeRecord(bundleURL: URL) async -> AppRecord? {
    // … read Info.plist, resolve symlinks …
    return await MainActor.run {
        let icon = NSWorkspace.shared.icon(forFile: resolvedPath)
        icon.size = NSSize(width: LauncherDimensions.resultIconSize,
                           height: LauncherDimensions.resultIconSize)
        return AppRecord(...)
    }
}
```

This hop is the convention at work: the compiler accepts the icon call, the `icon.size` mutation, and the `AppRecord` init without it.

In a synchronous `@Sendable` callback, use `Task { @MainActor in … }`, as `AppLauncher.launch(_:)` and `PanelController.observeResults()` do. The attribute is required: a bare `Task` inside a `@Sendable` closure inherits no isolation and can't reach main-actor code.

`MainActor.run` requires the closure's return type to be `Sendable`. `AppRecord` is declared `@unchecked Sendable`, under this contract: the `NSImage` is mutated only inside the main-actor block, then the record is immutable, then it crosses back to the nonisolated scan for collection. The compiler enforces none of this and doesn't require the annotation, because a default-isolated struct is implicitly `Sendable` and `NSImage` is `Sendable` through its `Transferable` conformance. That "assembled on main, then immutable" contract is the *only* basis on which `@unchecked Sendable` is acceptable in this codebase — when the immutability isn't obvious from the surrounding code, justify the `@unchecked` with a comment.

## FSEvents wrapper: the ContinuationBox pattern

`FileWatcher` (in `Sources/Config/FileWatcher.swift`) wraps `FSEventStream` so changes to disk yield `Void` events over an `AsyncStream`. FSEvents' callback runs on a global dispatch queue and references its `info` pointer via Swift's `Unmanaged`.

**Stream setup.** `FSEventStreamSetDispatchQueue` targets `DispatchQueue.global(qos: .utility)`. The flags are `kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents`, starting from `kFSEventStreamEventIdSinceNow` with `coalesceLatencySeconds` of 1.0: the first event after a quiet period arrives immediately and later ones batch. The callback ignores paths and flags and yields one `Void` per delivery, and the stream is `.bufferingNewest(1)`, so events arriving while the consumer is busy collapse into one pending element. Consumers learn only that something changed. Empty `paths` or a failed `FSEventStreamCreate` finishes the stream immediately.

**What gets watched.** At startup `AppDelegate` attaches one watcher to the config file's directory and one to the configured app directories (see `overview.md`). Config and frecency are saved with atomic writes (`Data.write(to:options: .atomic)`), which replace the file's inode on every save, but FSEvents follows paths, not inodes: with `kFSEventStreamCreateFlagFileEvents` a stream on the file's own path keeps firing across atomic saves, while without that flag a stream on a file path never fires. The directory watch has a cost. The stream doesn't set `kFSEventStreamCreateFlagIgnoreSelf`, so frecency saves and `ConfigStore`'s own writes fire the config watcher, and `startConfigWatcher()` compares the reloaded `Config` before rescanning.

**Consuming it.** `AppDelegate` keeps each watcher in a stored property and loops over `watcher.events` in a `Task { [weak self] in … }`. The task captures only `events`, never the watcher, so reassigning the property deallocates the old `FileWatcher`. Its `deinit` runs stop, invalidate, and release on the stream, then `continuation.finish()`, which ends the old loop. `stream` is `nonisolated(unsafe)`: it's written once at the end of `init` and read in `deinit`.

**The hazard.** The naive pattern — `Unmanaged.passUnretained(self)` with `nil` retain/release on `FSEventStreamContext` — leaves a raw pointer to the watcher in FSEvents' hands. If the watcher is deallocated (e.g. replaced when the config changes) while a callback is still draining on the global queue, the callback dereferences a dangling pointer.

**The fix.** Allocate a `ContinuationBox` class holding the `AsyncStream.Continuation` separately from the `FileWatcher`. Configure `FSEventStreamContext` with `retain` and `release` callbacks that bump the box's refcount via `Unmanaged.retain()` / `.release()`. FSEvents keeps the box alive as long as the stream exists, independent of whether `FileWatcher` itself is gone.

**Closure isolation is the other half.** The `retain`, `release`, and event-delivery callbacks must be declared `nonisolated` — either as top-level `nonisolated` functions (as `FileWatcher.swift` does) or as `nonisolated static let` constants on a non-actor namespace. A closure literal or unannotated function in this file inherits `@MainActor` from `-default-isolation MainActor`, and Swift 6 emits a runtime executor check at its entry. Nothing catches this at build time: both forms typecheck cleanly as C callbacks. FSEvents invokes those callbacks from the queue set with `FSEventStreamSetDispatchQueue` (utility-qos for `FileWatcher`), so the check trips `dispatch_assert_queue` and brings the process down — typically during stream teardown inside `_FSEventStreamDeallocate`, fired when a `FileWatcher` is reassigned (e.g. `startAppWatcher()` after a config-dir event). The trap is invisible in OSLog because SIGTRAP bypasses log buffer flush; look in `~/Library/Logs/DiagnosticReports/Borma-*.ips`.

If you write more `FSEventStream`-style wrappers, follow the same pattern: box for refcount, top-level `nonisolated` functions for the C callbacks.

## Custom `Shape`s and `LauncherDimensions` are `nonisolated`

SwiftUI declares `Shape` as a `nonisolated`, `Sendable` protocol with a `nonisolated func path(in:)` requirement, and calls it off the main actor. Under `-default-isolation MainActor` an unannotated `struct Foo: Shape` is implicitly `@MainActor`, so its `path(in:)` can't satisfy the requirement and the build fails with `conformance of 'Foo' to protocol 'Shape' crosses into main actor-isolated code` (`#ConformanceIsolation`).

- **Custom shapes:** declare them `nonisolated struct` — `LauncherSurface` in `Sources/Panel/SearchView.swift` is the example. Don't reach for the compiler's other suggestions. An `@MainActor` isolated conformance is illegal on a `Sendable` protocol. `@preconcurrency` doesn't compile either, despite the note offering to `turn data races into runtime errors`: the conformance still errors (`involves isolation mismatches`) and the attribute is reported as having no effect. Marking only `path(in:)` `nonisolated` does compile, but leaves the rest of the struct main-actor.
- **Constants read from shapes:** `Sources/Panel/LayoutMetrics.swift` is `nonisolated enum LauncherDimensions` so `path(in:)` and the shapes' stored-property defaults can read it. `LauncherSurface`'s `cornerRadius` and `notchRadius` defaults are the current readers. Don't add main-actor isolation to it: a default then fails with `main actor-isolated default value in a nonisolated context`, and a `path(in:)` body with `main actor-isolated static property ... can not be referenced from a nonisolated context`.

## SwiftUI observation

`@Observable` types (`LauncherModel`, `ConfigStore`) are main-actor by default under the isolation flag. Their stored properties are read/written from the main thread; SwiftUI's observation mechanism handles change tracking.

`@ObservationIgnored` is used for closure properties (`onLaunch`, `onDismissRequested`) so reassigning them doesn't trigger re-renders, and on `ConfigStore.fileURL`.

`PanelController.observeResults()` tracks outside SwiftUI with `withObservationTracking`. Its `onChange` closure is `@Sendable` and nonisolated, so it hops with `Task { @MainActor [weak self] in … }`. `panel.md` covers what it tracks and how it re-arms.

## Iterating sequences inside async contexts

`NSEnumerator.makeIterator()` is `@available(*, noasync)`, and `FileManager.DirectoryEnumerator` inherits it. Calling `for case let url as URL in enumerator { ... }` inside an `async` function fails to compile in Swift 6 (`instance method 'makeIterator' is unavailable from asynchronous contexts`). Drain into an array first:

```swift
for case let url as URL in enumerator.allObjects where url.pathExtension == "app" {
    candidates.append(url)
}
```

`allObjects` eagerly enumerates and returns `[Any]`, which iterates fine.

## See also
- `overview.md` — watcher data flow and persistence locations
- `panel.md` — the properties `observeResults()` tracks and why
