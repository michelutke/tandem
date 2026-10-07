import Testing

@testable import TandemApp
@testable import TandemProtocol
import TandemTransport

/// E22-01 tdd (unit): ``MenuBarViewModel`` mapping ``ConnectionStateMachine/ConnectionState``
/// transitions from the E12-12 `FakeTandemSession` into the menu bar's own presentation state.
@Suite("MenuBarViewModel")
struct MenuBarViewModelTests {
    // MARK: - menuBarViewModel_sessionStateTransition_publishesWithin1s

    @Test
    func menuBarViewModel_sessionStateTransition_publishesWithin1s() async throws {
        let session = FakeTandemSession()
        let viewModel = await MenuBarViewModel(stateStream: session.state, peerName: "Pixel 8")

        await session.emit(.ready)

        // This package's `injected_clock_only` SwiftLint rule (E00-24) bans the usual real-time
        // sleep/now APIs outright, even in test files -- so this yields cooperatively, bounded by
        // an iteration count rather than a wall-clock deadline, until the observation `Task` has
        // had a chance to run. In practice this settles within one or two yields, nowhere near
        // the acceptance's 1 s bound.
        var attempts = 0
        while await viewModel.state != .connected(peerName: "Pixel 8"), attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        #expect(await viewModel.state == .connected(peerName: "Pixel 8"))
        #expect(await viewModel.label == "Connected to Pixel 8")
    }

    // MARK: - menuBarViewModel_eachConnectionState_distinctIconAndExactLabel

    @Test @MainActor
    func menuBarViewModel_eachConnectionState_distinctIconAndExactLabel() {
        let cases: [(state: MenuBarViewModel.State, label: String)] = [
            (.notPaired, "Not paired"),
            (.connecting, "Connecting…"),
            (.connected(peerName: "Pixel 8"), "Connected to Pixel 8"),
            (.reconnecting, "Reconnecting…"),
            (.disconnected, "Disconnected"),
            (.error, "Error")
        ]

        var icons = Set<String>()
        for testCase in cases {
            let viewModel = MenuBarViewModel(state: testCase.state)
            #expect(viewModel.label == testCase.label)
            icons.insert(viewModel.systemImageName)
        }

        #expect(icons.count == cases.count, "every state should map to a distinct icon")
    }

    // MARK: - menuBarViewModel_noPairedPeer_labelNotPaired

    @Test @MainActor
    func menuBarViewModel_noPairedPeer_labelNotPaired() {
        let viewModel = MenuBarViewModel(stateStream: nil, peerName: nil)

        #expect(viewModel.state == .notPaired)
        #expect(viewModel.label == "Not paired")
        #expect(viewModel.showsPairPhoneMenuItem)
    }

    // MARK: - menuBarViewModel_willSleepThenDidWake_reconnectingThenConnected

    /// E22-08 tdd (unit): after ``SystemPowerEvent/willSleep`` then ``SystemPowerEvent/didWake``
    /// (``FakeSystemPowerEvents``, E20-10's own seam, shared via `TandemTestSupport`), the label
    /// reads "Reconnecting…" until the underlying session (E12-12 `FakeTandemSession`) reaches
    /// `.ready` again, matching this issue's acceptance criterion exactly.
    @Test
    func menuBarViewModel_willSleepThenDidWake_reconnectingThenConnected() async throws {
        let session = FakeTandemSession()
        let powerEvents = FakeSystemPowerEvents()
        let viewModel = await MenuBarViewModel(
            stateStream: session.state,
            peerName: "Pixel 8",
            powerEvents: powerEvents
        )

        powerEvents.send(.willSleep)
        powerEvents.send(.didWake)

        var attempts = 0
        while await viewModel.state != .reconnecting, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        #expect(await viewModel.state == .reconnecting)
        #expect(await viewModel.label == "Reconnecting…")

        await session.emit(.ready)

        attempts = 0
        while await viewModel.state != .connected(peerName: "Pixel 8"), attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        #expect(await viewModel.state == .connected(peerName: "Pixel 8"))
        #expect(await viewModel.label == "Connected to Pixel 8")
    }

    // MARK: - menuBarViewModel_pathInterfaceChanged_reconnectingWithin1s

    /// E22-08 tdd (unit): an interface-set change on ``NetworkPathSource`` (``FakeNetworkPathSource``,
    /// E20-11's own seam, shared via `TandemTestSupport`) shows "Reconnecting…" well within the
    /// acceptance's 1 s bound -- proved the same way ``menuBarViewModel_sessionStateTransition_publishesWithin1s``
    /// already does, a yield-bounded loop rather than a wall-clock deadline (this package's
    /// `injected_clock_only` SwiftLint rule, E00-24), with a ``ManualTestClock`` threaded through as
    /// this view model's own seam. The very first snapshot only seeds the baseline (mirrors
    /// `PathChangeController`) -- it alone must never flip the state to `.reconnecting`.
    @Test
    func menuBarViewModel_pathInterfaceChanged_reconnectingWithin1s() async throws {
        let clock = ManualTestClock()
        let session = FakeTandemSession()
        let pathSource = FakeNetworkPathSource()
        let viewModel = await MenuBarViewModel(
            stateStream: session.state,
            peerName: "Pixel 8",
            clock: clock,
            pathSource: pathSource
        )

        pathSource.send(NetworkPathSnapshot(interfaces: ["en0"]))
        await settle()
        #expect(await viewModel.state != .reconnecting, "the first snapshot only seeds the baseline")

        pathSource.send(NetworkPathSnapshot(interfaces: ["en0", "utun0"]))

        var attempts = 0
        while await viewModel.state != .reconnecting, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        #expect(await viewModel.state == .reconnecting)
        #expect(await viewModel.label == "Reconnecting…")
    }

    // MARK: - menuBarViewModel_realConnectionStateStream_reflectsReadyAndOfflineTransitions

    /// E22-11 tdd (unit): a real ``ConnectionStateRelay`` -- the same seam ``AppComposition`` wires
    /// into production -- keeps forwarding into one ``MenuBarViewModel`` across a reconnect: a first
    /// `FakeTandemSession` reaching `.ready` shows `.connected`, that same session closing shows
    /// `.disconnected` (real "offline"), and a second session (this peer's own reconnect)
    /// ``ConnectionStateRelay/attach(_:)``ed to the same relay reaching `.ready` again shows
    /// `.connected` again -- proving the relay, not just the already-tested pure view model, is what
    /// survives a real reconnect.
    @Test
    func menuBarViewModel_realConnectionStateStream_reflectsReadyAndOfflineTransitions() async throws {
        let relay = ConnectionStateRelay()
        let viewModel = await MenuBarViewModel(stateStream: relay.makeStream(), peerName: "Pixel 8")

        let firstSession = FakeTandemSession()
        await relay.attach(firstSession)
        await firstSession.emit(.ready)

        var attempts = 0
        while await viewModel.state != .connected(peerName: "Pixel 8"), attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }
        #expect(await viewModel.state == .connected(peerName: "Pixel 8"))

        await firstSession.close()

        attempts = 0
        while await viewModel.state != .disconnected, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }
        #expect(await viewModel.state == .disconnected)

        let secondSession = FakeTandemSession()
        await relay.attach(secondSession)
        await secondSession.emit(.ready)

        attempts = 0
        while await viewModel.state != .connected(peerName: "Pixel 8"), attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }
        #expect(await viewModel.state == .connected(peerName: "Pixel 8"))
    }

    @Test
    func menuBarViewModel_pairedPeer_exposesDisplayNameInEveryState() async {
        let paired = await MenuBarViewModel(stateStream: nil, peerName: "Pixel 9")
        let unpaired = await MenuBarViewModel(stateStream: nil, peerName: nil)

        #expect(await paired.displayName == "Pixel 9")
        #expect(await unpaired.displayName == nil)
    }

    /// Yields several times so a view model's background observation `Task` has a chance to consume
    /// an event already sent on a fake stream, without an artificial wall-clock sleep -- mirrors
    /// `SleepWakeControllerTests`/`PathChangeControllerTests`'s own `settle()`.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}
