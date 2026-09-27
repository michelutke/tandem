import Testing

@testable import TandemApp
@testable import TandemProtocol

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
}
