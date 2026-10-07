import Testing
@testable import FeatureMirror
@testable import TandemProtocol

@MainActor
@Suite("MirrorRequestViewModel")
struct MirrorRequestViewModelTests {
    @Test
    func mirrorQuickAction_clicked_sendsOneMirrorRequestAndNoTicket() async {
        let session = FakeTandemSession()
        let model = MirrorRequestViewModel(session: session)

        model.request()

        let sent = await waitUntilTrue { await session.sent.count == 1 }
        #expect(sent)
        let frames = await session.sent
        #expect(frames.map(\.channel) == [.control])
        guard case .mirrorRequest = frames[0].payload else {
            Issue.record("expected mirrorRequest, got \(frames[0].payload)")
            return
        }
        #expect(model.state == .waiting)
        #expect(model.statusText == "Accept on phone to start.")
    }

    @Test
    func mirrorQuickAction_noSession_showsPhoneNotConnected() async {
        let model = MirrorRequestViewModel(session: nil)

        model.request()

        #expect(model.state == .notConnected)
        #expect(model.statusText == "Phone not connected.")
    }

    @Test
    func mirrorQuickAction_sessionAttachedAfterNotConnected_requestReachesSession() async {
        let session = FakeTandemSession()
        let model = MirrorRequestViewModel(session: nil)
        model.request()

        await model.sessionChanged(session)
        model.request()

        #expect(await waitUntilTrue { await session.sent.count == 1 })
        #expect(model.state == .waiting)
    }

    @Test
    func mirrorQuickAction_requestPending_noTicketUntilPhoneRequestsOne() async {
        let session = FakeTandemSession()
        let model = MirrorRequestViewModel(session: session)

        model.request()
        model.request()
        _ = await waitUntilTrue { await session.sent.count == 1 }
        for _ in 0..<20 { await Task.yield() }

        let frames = await session.sent
        #expect(frames.count == 1)
        for frame in frames {
            if case .mediaTicketGrant = frame.payload { Issue.record("ticket issued before phone request") }
        }
    }

    @Test
    func mirrorQuickAction_mirrorDeclinedReceived_statusShowsDeclinedOnPhone() async {
        let session = FakeTandemSession()
        let model = MirrorRequestViewModel(session: session)
        await model.start()
        model.request()

        await session.inject(InboundFrame(
            channel: .control, seq: 0, ack: 0, payload: .mirrorDeclined(Tandem_V1_MirrorDeclined())))

        let declined = await waitUntilTrue { model.state == .declined }
        #expect(declined)
        #expect(model.statusText == "Mirroring declined on phone")
    }

    @Test
    func mirrorQuickAction_unsolicitedMirrorDeclined_ignored() async {
        let session = FakeTandemSession()
        let model = MirrorRequestViewModel(session: session)
        await model.start()

        await session.inject(InboundFrame(
            channel: .control, seq: 0, ack: 0, payload: .mirrorDeclined(Tandem_V1_MirrorDeclined())))
        for _ in 0..<20 { await Task.yield() }

        #expect(model.state == .idle)
        #expect(model.statusText == nil)
    }

    @Test
    func mirrorQuickAction_declinedThenRequestAgain_sendsSecondRequest() async {
        let session = FakeTandemSession()
        let model = MirrorRequestViewModel(session: session)
        await model.start()
        model.request()
        await session.inject(InboundFrame(
            channel: .control, seq: 0, ack: 0, payload: .mirrorDeclined(Tandem_V1_MirrorDeclined())))
        _ = await waitUntilTrue { model.state == .declined }

        model.request()

        let resent = await waitUntilTrue { await session.sent.count == 2 }
        #expect(resent)
        #expect(model.state == .waiting)
    }

    @Test
    func mirrorQuickAction_cancel_returnsToIdle() {
        let model = MirrorRequestViewModel(session: FakeTandemSession())
        model.request()
        model.cancel()
        #expect(model.state == .idle)
        #expect(model.statusText == nil)
    }

    private func waitUntilTrue(_ condition: @MainActor () async -> Bool) async -> Bool {
        for _ in 0..<2000 {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }

    @Test
    func mirrorRequestViewModel_sessionChanged_sendsOnNewSessionOnly() async {
        let first = FakeTandemSession()
        let second = FakeTandemSession()
        let model = MirrorRequestViewModel(session: first)

        await model.sessionChanged(second)
        model.request()

        let sent = await waitUntilTrue { await second.sent.count == 1 }
        #expect(sent)
        #expect(await first.sent.isEmpty)
    }
}
