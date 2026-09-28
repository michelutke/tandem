import AppKit
import Testing
@testable import FeatureClipboard
@testable import TandemTestSupport

/// E31-02: ``PasteboardPoller`` polls ``PasteboardSource/changeCount`` every 250 ms on a
/// background timer driven by an injected `Clock<Duration>`, never real wall-clock time -- see
/// `PasteboardPollerTestSupport.swift`'s own doc comment for the `ManualTestClock` parking hazard
/// these tests avoid via `waitForParkedSleepers(_:count:)`.
@Suite("PasteboardPoller", .serialized)
struct PasteboardPollerTests {

    @Test
    func pasteboardPoller_changeCountIncremented_detectedAfterAdvance250ms() async throws {
        let clock = ManualTestClock()
        let source = FakePasteboardSource(changeCount: 0, types: [.string])
        let collector = DetectionCollector()
        let poller = PasteboardPoller(source: source, clock: clock) { types in
            await collector.record(types)
        }

        await poller.start()
        let parked = await waitForParkedSleepers(clock, count: 1)
        #expect(parked)

        source.changeCount = 1
        clock.advance(by: PasteboardPoller.pollInterval)

        let detected = await waitUntilTrue { await collector.detections.count == 1 }
        #expect(detected, "expected a detection once the clock advances one poll interval")
        #expect(await collector.detections == [[.string]])
    }

    @Test
    func pasteboardPoller_changeCountUnchanged_noDetectionAfterAdvance10s() async throws {
        let clock = ManualTestClock()
        let source = FakePasteboardSource(changeCount: 5, types: [.string])
        let collector = DetectionCollector()
        let poller = PasteboardPoller(source: source, clock: clock) { types in
            await collector.record(types)
        }

        await poller.start()
        #expect(await waitForParkedSleepers(clock, count: 1))

        var elapsed: Duration = .zero
        while elapsed < .seconds(10) {
            clock.advance(by: PasteboardPoller.pollInterval)
            elapsed += PasteboardPoller.pollInterval
            // Let each tick's loop iteration re-park before the next advance -- otherwise a later
            // advance could compute its own deadline against an already-moved `now` and silently
            // skip a tick (see PasteboardPollerTestSupport.swift's doc comment).
            #expect(await waitForParkedSleepers(clock, count: 1))
        }

        #expect(await collector.detections.isEmpty, "changeCount never changed, so no detection must fire")
    }

    @Test
    func pasteboardPoller_twoChangesWithinInterval_singleDetectionOfLatest() async throws {
        let clock = ManualTestClock()
        let source = FakePasteboardSource(changeCount: 0, types: [.string])
        let collector = DetectionCollector()
        let poller = PasteboardPoller(source: source, clock: clock) { types in
            await collector.record(types)
        }

        await poller.start()
        #expect(await waitForParkedSleepers(clock, count: 1))

        // Two changes land before the poller's next tick -- it must only ever compare against the
        // last-seen changeCount at the tick, so this collapses to one detection of the final state.
        source.changeCount = 1
        source.typesToReturn = [.string]
        source.changeCount = 2
        source.typesToReturn = [.fileURL]

        clock.advance(by: PasteboardPoller.pollInterval)

        let detected = await waitUntilTrue { await collector.detections.count == 1 }
        #expect(detected)
        #expect(await collector.detections == [[.fileURL]])

        // Confirm no further, delayed second detection ever arrives for the intermediate change.
        clock.advance(by: PasteboardPoller.pollInterval)
        await realDelay(milliseconds: 20)
        #expect(await collector.detections.count == 1)
    }
}
