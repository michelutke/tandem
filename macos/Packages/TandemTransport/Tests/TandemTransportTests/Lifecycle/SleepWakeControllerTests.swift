import Foundation
import Synchronization
import Testing
import TandemTestSupport
@testable import TandemTransport

/// E20-10 (docs/protocol/SPEC.md #heartbeat, PRD F-3.4, UC-04): ``SleepWakeController`` stops the
/// listener on ``SystemPowerEvent/willSleep`` and restarts it on ``SystemPowerEvent/didWake``,
/// against a recording ``ListenerControl`` fake and a ``SystemPowerEvents`` fake this file drives
/// directly -- no real `NSWorkspace` notification and no wall-clock sleep in any test here
/// (``ManualTestClock``, E00-24, stands in for the 1 s bound).
@Suite("SleepWakeController")
struct SleepWakeControllerTests {

    @Test
    func sleepWakeController_willSleep_listenerStoppedAndConnectionsDisconnected() async {
        let listenerControl = FakeListenerControl()
        let powerEvents = FakeSystemPowerEvents()
        let controller = SleepWakeController(powerEvents: powerEvents, listenerControl: listenerControl)
        await controller.start()

        powerEvents.send(.willSleep)
        await settle()

        // `ListenerControl.stop()`'s documented contract (this package's `ListenerControl.swift`)
        // is to both stop accepting new connections and move every open connection to
        // `Disconnected` (E12-09) -- the one call this fake records proves both halves of the
        // acceptance criterion.
        #expect(listenerControl.stopCallCount == 1)
    }

    @Test
    func sleepWakeController_didWake_listenerReadyWithin1s() async {
        let clock = ManualTestClock()
        let listenerControl = FakeListenerControl(clock: clock, startDelay: .milliseconds(500))
        let powerEvents = FakeSystemPowerEvents()
        let controller = SleepWakeController(powerEvents: powerEvents, listenerControl: listenerControl)
        await controller.start()

        powerEvents.send(.willSleep)
        await settle()
        #expect(listenerControl.stopCallCount == 1)

        powerEvents.send(.didWake)
        await settle()

        #expect(
            !listenerControl.isRunning,
            "the fake's simulated startup latency has not elapsed yet on the manual clock"
        )

        clock.advance(by: .milliseconds(500))
        await settle()

        #expect(listenerControl.startCallCount == 1)
        #expect(listenerControl.isRunning, "listener must be ready well within the 1 s bound")
    }

    @Test
    func sleepWakeController_didWakeWithoutSleep_noDuplicateListener() async {
        let listenerControl = FakeListenerControl()
        let powerEvents = FakeSystemPowerEvents()
        let controller = SleepWakeController(powerEvents: powerEvents, listenerControl: listenerControl)
        await controller.start()

        powerEvents.send(.didWake)
        await settle()

        #expect(listenerControl.startCallCount == 0)
        #expect(listenerControl.stopCallCount == 0)
    }

    /// Yields several times so the actor's background observation `Task` has a chance to consume
    /// events already sent on ``FakeSystemPowerEvents``, without an artificial wall-clock sleep.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

/// Recording ``SystemPowerEvents`` fake driven directly by ``send(_:)``, standing in for a real
/// `NSWorkspace` notification stream in ``SleepWakeControllerTests``.
final class FakeSystemPowerEvents: SystemPowerEvents, @unchecked Sendable {
    let events: AsyncStream<SystemPowerEvent>
    private let continuation: AsyncStream<SystemPowerEvent>.Continuation

    init() {
        (events, continuation) = AsyncStream<SystemPowerEvent>.makeStream()
    }

    func send(_ event: SystemPowerEvent) {
        continuation.yield(event)
    }
}

/// Recording ``ListenerControl`` fake. `startDelay`, driven by an injected `Clock<Duration>`
/// (``ManualTestClock`` in tests), simulates ``start()`` taking some bounded time to reach ready --
/// deterministically, never via a real wall-clock sleep.
final class FakeListenerControl: ListenerControl, Sendable {
    private struct State {
        var startCallCount = 0
        var stopCallCount = 0
        var isRunning = false
    }

    private let clock: any Clock<Duration>
    private let startDelay: Duration
    private let state = Mutex(State())

    init(clock: any Clock<Duration> = ManualTestClock(), startDelay: Duration = .zero) {
        self.clock = clock
        self.startDelay = startDelay
    }

    var startCallCount: Int {
        state.withLock { $0.startCallCount }
    }

    var stopCallCount: Int {
        state.withLock { $0.stopCallCount }
    }

    var isRunning: Bool {
        state.withLock { $0.isRunning }
    }

    func start() async throws {
        state.withLock { $0.startCallCount += 1 }

        if startDelay > .zero {
            try? await clock.sleep(for: startDelay)
        }

        state.withLock { $0.isRunning = true }
    }

    func stop() async {
        state.withLock {
            $0.stopCallCount += 1
            $0.isRunning = false
        }
    }
}
