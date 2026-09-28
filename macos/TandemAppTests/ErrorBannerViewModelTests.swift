import Testing

@testable import TandemApp
@testable import TandemProtocol

/// E22-07 tdd (unit): ``ErrorBannerViewModel`` mapping fail-closed
/// ``ConnectionStateMachine/ConnectionState/failed(_:)`` events from the E12-12 `FakeTandemSession`
/// into a persistent, secret-free banner (invariant 5). Mirrors ``MenuBarViewModelTests``'s own
/// conventions. ``ManualTestClock`` (E00-24) is compiled directly into this test target from its
/// canonical `TandemTestSupport` source file (see `project.yml`'s own comment) rather than via a
/// `package: TandemTestSupport` dependency, so it needs no import here -- same module.
@Suite("ErrorBannerViewModel")
struct ErrorBannerViewModelTests {
    // MARK: - errorBannerViewModel_pinMismatchEvent_showsExactMessageWithPeerName

    @Test
    func errorBannerViewModel_pinMismatchEvent_showsExactMessageWithPeerName() async throws {
        let session = FakeTandemSession()
        let viewModel = await ErrorBannerViewModel(stateStream: session.state, peerName: "Pixel 8")

        await session.emit(.failed(.pinMismatch))

        var attempts = 0
        while await viewModel.message == nil, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        #expect(await viewModel.message == "Pixel 8 presented an unexpected key. Connection refused.")
    }

    // MARK: - errorBannerViewModel_unknownPeerEvent_showsExactRefusedMessage

    @Test
    func errorBannerViewModel_unknownPeerEvent_showsExactRefusedMessage() async throws {
        let session = FakeTandemSession()
        let viewModel = await ErrorBannerViewModel(stateStream: session.state, peerName: nil)

        await session.emit(.failed(.pinMismatch))

        var attempts = 0
        while await viewModel.message == nil, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        #expect(await viewModel.message == "An unpaired device tried to connect and was refused.")
    }

    // MARK: - errorBannerViewModel_versionMismatchEvent_showsExactUpdateMessage

    @Test
    func errorBannerViewModel_versionMismatchEvent_showsExactUpdateMessage() async throws {
        let session = FakeTandemSession()
        let viewModel = await ErrorBannerViewModel(stateStream: session.state, peerName: "Pixel 8")

        await session.emit(.failed(.versionMismatch))

        var attempts = 0
        while await viewModel.message == nil, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        #expect(await viewModel.message == "Pixel 8 runs an incompatible Tandem version. Update both apps.")
    }

    // MARK: - errorBannerViewModel_after1hWithoutAck_bannerStillShown

    @Test
    func errorBannerViewModel_after1hWithoutAck_bannerStillShown() async throws {
        let clock = ManualTestClock()
        let session = FakeTandemSession()
        let viewModel = await ErrorBannerViewModel(
            stateStream: session.state,
            peerName: "Pixel 8",
            clock: clock
        )

        await session.emit(.failed(.versionMismatch))

        var attempts = 0
        while await viewModel.message == nil, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        clock.advance(by: .seconds(3600))

        #expect(await viewModel.message == "Pixel 8 runs an incompatible Tandem version. Update both apps.")
    }

    // MARK: - errorBannerViewModel_okTapped_bannerDismissed

    @Test
    func errorBannerViewModel_okTapped_bannerDismissed() async throws {
        let session = FakeTandemSession()
        let viewModel = await ErrorBannerViewModel(stateStream: session.state, peerName: "Pixel 8")

        await session.emit(.failed(.versionMismatch))

        var attempts = 0
        while await viewModel.message == nil, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        await viewModel.dismiss()

        #expect(await viewModel.message == nil)
    }
}
