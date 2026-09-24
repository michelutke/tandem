import Testing
@testable import TandemTestSupport

@Suite("ManualTestClock")
struct ManualTestClockTests {

    @Test
    func manualTestClock_advanceBy15s_resumesSleeperDueAt15s() async throws {
        let clock = ManualTestClock()
        let deadline = clock.now.advanced(by: .seconds(15))

        let sleeper = Task {
            try await clock.sleep(until: deadline)
        }

        while clock.pendingSleeperCountForTesting < 1 {
            await Task.yield()
        }

        clock.advance(by: .seconds(15))

        try await sleeper.value
        #expect(clock.pendingSleeperCountForTesting == 0)
    }

    @Test
    func manualTestClock_advanceBy14s_sleeperDueAt15sStillSuspended() async throws {
        let clock = ManualTestClock()
        let deadline = clock.now.advanced(by: .seconds(15))

        let sleeper = Task {
            try await clock.sleep(until: deadline)
        }

        while clock.pendingSleeperCountForTesting < 1 {
            await Task.yield()
        }

        clock.advance(by: .seconds(14))

        #expect(clock.pendingSleeperCountForTesting == 1)

        sleeper.cancel()
        _ = try? await sleeper.value
    }

    @Test
    func manualTestClock_twoSleepers_resumedInDeadlineOrder() async throws {
        let clock = ManualTestClock()
        let recorder = OrderRecorder()

        let laterDeadline = clock.now.advanced(by: .seconds(10))
        let earlierDeadline = clock.now.advanced(by: .seconds(5))

        let second = Task {
            try await clock.sleep(until: laterDeadline)
            await recorder.record(2)
        }
        let first = Task {
            try await clock.sleep(until: earlierDeadline)
            await recorder.record(1)
        }

        while clock.pendingSleeperCountForTesting < 2 {
            await Task.yield()
        }

        clock.advance(by: .seconds(10))

        _ = try await first.value
        _ = try await second.value

        #expect(await recorder.order == [1, 2])
    }

    @Test
    func manualTestClock_pairingWindow120s_completesInUnderOneSecondRealTime() async throws {
        let clock = ManualTestClock()
        let deadline = clock.now.advanced(by: .seconds(120))

        let sleeper = Task {
            try await clock.sleep(until: deadline)
        }

        while clock.pendingSleeperCountForTesting < 1 {
            await Task.yield()
        }

        let wallClockStart = ContinuousClock.now
        clock.advance(by: .seconds(120))
        try await sleeper.value
        let wallClockElapsed = ContinuousClock.now - wallClockStart

        #expect(wallClockElapsed < .seconds(1))
    }
    @Test(.timeLimit(.minutes(1)))
    func manualTestClock_sleeperCancelled_throwsCancellationWithoutAdvance() async throws {
        let clock = ManualTestClock()
        for _ in 0..<200 {
            let sleeper = Task {
                try await clock.sleep(until: clock.now.advanced(by: .seconds(60)))
            }
            sleeper.cancel()
            await #expect(throws: CancellationError.self) { try await sleeper.value }
        }
        #expect(clock.pendingSleeperCountForTesting == 0)
    }
}

private actor OrderRecorder {
    private(set) var order: [Int] = []

    func record(_ id: Int) {
        order.append(id)
    }

}
