---
scope: Swift 6 -default-isolation MainActor, AppKit main-hops, FSEvents ContinuationBox, Sendable
globs:
  - Sources/Config/FileWatcher.swift
  - Sources/Panel/LayoutMetrics.swift
  - Sources/Search/Apps.swift
keywords: [MainActor, default-isolation, Sendable, unchecked Sendable, nonisolated, AsyncStream, FSEvents, ContinuationBox, Task.detached, MainActor.run, Shape, observation, DirectoryEnumerator, Sendable warning or error, data race, FSEvents callback after dealloc, EXC_BREAKPOINT in _FSEventStreamDeallocate, dispatch_assert_queue trap on utility-qos, Shape cannot read main-actor constant, DirectoryEnumerator makeIterator unavailable from async]
updated: 2026-06-06
---

# Concurrency

Borma builds under Swift 6 with `-default-isolation MainActor` set in `project.yml`. Every declaration is implicitly `@MainActor` unless explicitly marked otherwise.

## What "default-isolation MainActor" means

- Top-level functions, types, properties, and methods are `@MainActor` without needing the attribute.
- Adding `@MainActor` to a declaration that's already inside main-actor isolation is redundant. **Don't.**
- To opt out, mark with `nonisolated` (or move into an actor / Sendable type).

Example: `AppScanner`'s scan methods (`scanAsync`, `makeRecord`) are explicitly `nonisolated` so the directory walk runs off-main under `Task.detached`. `Matcher`, by contrast, is a pure utility that happens to run *on* main — it's only ever called from `LauncherModel.results`, a main-actor computed property — so it's left at default isolation. Being a pure function doesn't require `nonisolated`; needing to run off-main does.

## AppKit is main-actor-only

`NSWorkspace`, `NSScreen`, `NSPanel`, `NSImage`, and friends are main-actor APIs. Calling them from a background actor is unsafe.

**Stay on main.** If the work is fast, just call directly — the default isolation puts you on main anyway.

**Hop back to main for the AppKit call.** If you're in a `Task.detached` or `nonisolated` function and need an AppKit object, wrap the call in `MainActor.run`:

```swift
nonisolated func makeRecord(bundleURL: URL) async -> AppRecord {
    // … background work …
    return await MainActor.run {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: LauncherDimensions.resultIconSize,
                           height: LauncherDimensions.resultIconSize)
        return AppRecord(...)
    }
}
```

`MainActor.run` requires the closure's return type to be `Sendable`. `AppRecord` is `@unchecked Sendable` for this reason: the `NSImage` is mutated only inside the main-actor block, then the record is immutable, then it crosses back to the background actor for collection.

See `Sources/Search/Apps.swift` for the canonical example.

## FSEvents wrapper: the ContinuationBox pattern

`FileWatcher` (in `Sources/Config/FileWatcher.swift`) wraps `FSEventStream` so changes to disk yield `Void` events over an `AsyncStream`. FSEvents' callback runs on a global dispatch queue and references its `info` pointer via Swift's `Unmanaged`.

**The hazard.** The naive pattern — `Unmanaged.passUnretained(self)` with `nil` retain/release on `FSEventStreamContext` — leaves a raw pointer to the watcher in FSEvents' hands. If the watcher is deallocated (e.g. replaced when the config changes) while a callback is still draining on the global queue, the callback dereferences a dangling pointer.

**The fix.** Allocate a `ContinuationBox` class holding the `AsyncStream.Continuation` separately from the `FileWatcher`. Configure `FSEventStreamContext` with `retain` and `release` callbacks that bump the box's refcount via `Unmanaged.retain()` / `.release()`. FSEvents now keeps the box alive as long as the stream exists, independent of whether `FileWatcher` itself is gone.

**Closure isolation is the other half.** The `retain`, `release`, and event-delivery callbacks must be declared `nonisolated` — either as top-level `nonisolated` functions (as `FileWatcher.swift` does today) or as `nonisolated static let` constants on a non-actor namespace. A closure literal in this file inherits `@MainActor` from `-default-isolation MainActor`, and Swift 6 emits a runtime executor check at the closure prologue. FSEvents invokes those callbacks from its own dispatch queue (utility-qos for `FileWatcher`), so the check trips `dispatch_assert_queue` and brings the process down — typically during stream teardown inside `_FSEventStreamDeallocate`, fired when a `FileWatcher` is reassigned (e.g. `startAppWatcher()` after a config-dir event). The trap is invisible in OSLog because SIGTRAP bypasses log buffer flush; look in `~/Library/Logs/DiagnosticReports/Borma-*.ips`.

If you write more `FSEventStream`-style wrappers, follow the same pattern: box for refcount, top-level `nonisolated` functions for the C callbacks.

## `LauncherDimensions` is `nonisolated`

`Sources/Panel/LayoutMetrics.swift` is `nonisolated enum LauncherDimensions`. This is deliberate: SwiftUI calls `Shape.path(in:)` off the main actor under strict concurrency, and panel-layout code reads these constants from inside custom shapes. Don't add main-actor isolation to it.

## SwiftUI observation

`@Observable` types (`LauncherModel`, `ConfigStore`) are main-actor by default under the isolation flag. Their stored properties are read/written from the main thread; SwiftUI's observation mechanism handles change tracking.

`@ObservationIgnored` is used for closure properties (`onLaunch`, `onDismissRequested`) so reassigning them doesn't trigger re-renders.

## Iterating sequences inside async contexts

Some Foundation enumerator types (notably `FileManager.DirectoryEnumerator`) have `makeIterator` marked unavailable from async contexts in Swift 6. Calling `for case let url as URL in enumerator { ... }` inside an `async` function fails to compile. Drain into an array first:

```swift
for case let url as URL in enumerator.allObjects where url.pathExtension == "app" {
    candidates.append(url)
}
```

`allObjects` eagerly enumerates and returns `[Any]`, which iterates fine.
