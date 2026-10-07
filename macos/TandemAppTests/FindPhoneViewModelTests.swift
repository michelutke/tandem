import Testing

@testable import TandemApp
@testable import TandemProtocol

/// E23-07 tdd (unit): ``FindPhoneViewModel`` sending `Ring`/`RingStop` on the E12-12
/// `FakeTandemSession`'s STATUS channel and reacting to a phone-originated `RingStop`, the same
/// seam ``DeviceStatusViewModelTests`` already uses.
@Suite("FindPhoneViewModel")
struct FindPhoneViewModelTests {
    // MARK: - findPhoneViewModel_findPhoneSelected_sendsRingAndLabelStopRinging

    @Test
    func findPhoneViewModel_findPhoneSelected_sendsRingAndLabelStopRinging() async throws {
        let session = FakeTandemSession()
        let viewModel = await FindPhoneViewModel(session: session)

        await viewModel.select()

        #expect(await viewModel.label == "Stop Ringing")

        var attempts = 0
        while await session.sent.count < 1, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        let sent = await session.sent
        #expect(sent.count == 1)
        #expect(sent.first?.channel == .status)
        #expect(sent.first?.payload == .ring(Tandem_V1_Ring()))
    }

    // MARK: - findPhoneViewModel_stopRingingSelected_sendsRingStopAndLabelReverts

    @Test
    func findPhoneViewModel_stopRingingSelected_sendsRingStopAndLabelReverts() async throws {
        let session = FakeTandemSession()
        let viewModel = await FindPhoneViewModel(session: session)

        await viewModel.select()
        var attempts = 0
        while await session.sent.count < 1, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        await viewModel.select()

        #expect(await viewModel.label == "Find Phone")

        attempts = 0
        while await session.sent.count < 2, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        let sent = await session.sent
        #expect(sent.count == 2)
        #expect(sent.last?.channel == .status)
        var expectedRingStop = Tandem_V1_RingStop()
        expectedRingStop.origin = .mac
        #expect(sent.last?.payload == .ringStop(expectedRingStop))
    }

    // MARK: - findPhoneViewModel_ringStopFromPhone_labelRevertsToFindPhone

    @Test
    func findPhoneViewModel_ringStopFromPhone_labelRevertsToFindPhone() async throws {
        let session = FakeTandemSession()
        let viewModel = await FindPhoneViewModel(session: session)

        await viewModel.select()
        var attempts = 0
        while await session.sent.count < 1, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }
        #expect(await viewModel.label == "Stop Ringing")

        var ringStop = Tandem_V1_RingStop()
        ringStop.origin = .phone
        await session.inject(InboundFrame(channel: .status, seq: 1, ack: 0, payload: .ringStop(ringStop)))

        attempts = 0
        while await viewModel.label != "Find Phone", attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        #expect(await viewModel.label == "Find Phone")
        // No extra send in reaction to the phone's own RingStop -- only the earlier Ring is recorded.
        #expect(await session.sent.count == 1)
    }

    // MARK: - findPhoneViewModel_noSession_showsPhoneNotConnected

    @Test
    func findPhoneViewModel_noSession_showsPhoneNotConnected() async throws {
        let viewModel = await FindPhoneViewModel(session: nil)

        await viewModel.select()

        #expect(await viewModel.statusText == "Phone not connected.")
        #expect(await viewModel.label == "Find Phone")
    }

    // MARK: - findPhoneViewModel_sessionAttachedLater_ringReachesSessionAndClearsFeedback

    @Test
    func findPhoneViewModel_sessionAttachedLater_ringReachesSessionAndClearsFeedback() async throws {
        let session = FakeTandemSession()
        let viewModel = await FindPhoneViewModel(session: nil)
        await viewModel.select()

        await viewModel.sessionChanged(session)
        #expect(await viewModel.statusText == nil)
        await viewModel.select()

        var attempts = 0
        while await session.sent.count < 1, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }
        #expect(await session.sent.first?.payload == .ring(Tandem_V1_Ring()))
    }

    // MARK: - findPhoneViewModel_sessionDetached_ringingResetsAndSelectShowsFeedback

    @Test
    func findPhoneViewModel_sessionDetached_ringingResetsAndSelectShowsFeedback() async throws {
        let viewModel = await FindPhoneViewModel(session: FakeTandemSession())
        await viewModel.select()
        #expect(await viewModel.label == "Stop Ringing")

        await viewModel.sessionChanged(nil)
        #expect(await viewModel.label == "Find Phone")
        await viewModel.select()

        #expect(await viewModel.statusText == "Phone not connected.")
    }
}
