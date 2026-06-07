import CoreServices
import Foundation

final class FileWatcher: Sendable {
    let events: AsyncStream<Void>
    private let box: ContinuationBox
    private nonisolated(unsafe) var stream: FSEventStreamRef?

    /// Holds the AsyncStream continuation behind a heap reference so the
    /// FSEvents context can retain it via its own retain/release callbacks.
    /// FileWatcher then deallocates cleanly without leaving a dangling pointer
    /// to any callback the dispatch queue may still drain.
    fileprivate final class ContinuationBox: Sendable {
        let continuation: AsyncStream<Void>.Continuation
        init(_ continuation: AsyncStream<Void>.Continuation) {
            self.continuation = continuation
        }
    }

    init(paths: [String]) {
        let (events, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.events = events
        self.box = ContinuationBox(continuation)

        guard !paths.isEmpty else {
            continuation.finish()
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: fileWatcherRetain,
            release: fileWatcherRelease,
            copyDescription: nil
        )

        let flags = UInt32(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents)

        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            fileWatcherCallback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            FileWatcher.coalesceLatencySeconds,
            flags
        ) else {
            Log.app.error("FSEventStreamCreate failed for paths: \(paths, privacy: .public)")
            continuation.finish()
            return
        }

        FSEventStreamSetDispatchQueue(s, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(s)
        self.stream = s
    }

    /// FSEvents coalesces events arriving within this window before invoking
    /// the callback — long enough to batch a burst of writes, short enough
    /// that the user notices a live reload.
    private static let coalesceLatencySeconds: CFTimeInterval = 1.0

    deinit {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
        box.continuation.finish()
    }
}

// FSEvents invokes these on its dispatch queue, not on the main actor. They
// must be `nonisolated` — otherwise the file's `-default-isolation MainActor`
// setting parks a runtime executor check on the function prologue, which
// traps under `dispatch_assert_queue` the first time FSEvents calls in
// off-main (typically during stream teardown inside `_FSEventStreamDeallocate`).

private nonisolated func fileWatcherRetain(_ info: UnsafeRawPointer?) -> UnsafeRawPointer? {
    guard let info else { return nil }
    _ = Unmanaged<FileWatcher.ContinuationBox>.fromOpaque(info).retain()
    return info
}

private nonisolated func fileWatcherRelease(_ info: UnsafeRawPointer?) {
    guard let info else { return }
    Unmanaged<FileWatcher.ContinuationBox>.fromOpaque(info).release()
}

private nonisolated func fileWatcherCallback(
    _ stream: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ count: Int,
    _ paths: UnsafeMutableRawPointer,
    _ flags: UnsafePointer<UInt32>,
    _ ids: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let box = Unmanaged<FileWatcher.ContinuationBox>.fromOpaque(info).takeUnretainedValue()
    box.continuation.yield()
}
