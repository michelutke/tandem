import AppKit
import Foundation
import Testing
@testable import TandemTestSupport

/// Test harness pieces for ``PasteboardPollerTests``, split out to keep that file focused --
/// mirrors `TandemTransportTests`' own `HeartbeatControllerTestSupport` conventions for driving a
/// background-timer actor against a `ManualTestClock`.

/// Records every detection ``PasteboardPoller``'s `onChange` callback reports, off the actor under
/// test, so a test can assert on it after polling lets that callback actually run.
actor DetectionCollector {
    private(set) var detections: [[NSPasteboard.PasteboardType]] = []

    func record(_ types: [NSPasteboard.PasteboardType]) {
        detections.append(types)
    }
}

/// Polls `condition` until it is `true` or `timeout` elapses (real wall-clock time -- this is
/// purely a test-scheduling bound, unrelated to `ManualTestClock` under test), returning the final
/// result either way so a failure still reports "false" rather than hanging.
func waitUntilTrue(
    timeout: Duration = .seconds(2),
    _ condition: () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while true {
        if await condition() { return true }
        if ContinuousClock.now >= deadline { return await condition() }
        await Task.yield()
        await realDelay(milliseconds: 1)
    }
}

/// A short real-time (not `ManualTestClock`) delay, for polling loops that need to give some other
/// unstructured `Task` a scheduling opportunity. Deliberately not `Task.sleep` (E00-24's
/// `injected_clock_only` lint rule bars it outside `TandemTestSupport`/`TandemApp`) -- matches
/// `HeartbeatControllerTestSupport`'s own convention of reaching for `DispatchQueue.global()
/// .asyncAfter` for exactly this purpose.
func realDelay(milliseconds: Int) async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
            continuation.resume()
        }
    }
}

/// Polls ``ManualTestClock/pendingSleeperCountForTesting`` (internal, `@testable`-only) until it
/// reaches at least `count`. A poll-loop `Task` only registers with `clock` once it actually
/// reaches its own `clock.sleep(for:)` call, which can lag behind the actor call that started it
/// by an arbitrary, unstructured-`Task`-scheduling amount -- calling `clock.advance(by:)` before
/// that registration would compute the next deadline against the already-advanced `now`, silently
/// pushing it into the future.
func waitForParkedSleepers(
    _ clock: ManualTestClock,
    count: Int,
    timeout: Duration = .seconds(2)
) async -> Bool {
    await waitUntilTrue(timeout: timeout) { clock.pendingSleeperCountForTesting >= count }
}
