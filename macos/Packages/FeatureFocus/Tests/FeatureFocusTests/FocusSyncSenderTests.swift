import FeatureFocus
import Testing
@testable import TandemProtocol

@Suite struct FocusSyncSenderTests {
    private func makeSender() -> (FocusSyncSender, FakeTandemSession) {
        let session = FakeTandemSession()
        return (FocusSyncSender(source: RecordingFocusStateSource(), session: session), session)
    }

    private func focusStates(_ session: FakeTandemSession) async -> [Bool] {
        await session.sent.compactMap { frame in
            guard frame.channel == .control, case .focusState(let state) = frame.payload else { return nil }
            return state.on
        }
    }

    private func capability(available: Bool) -> Tandem_V1_FocusSyncCapability {
        var capability = Tandem_V1_FocusSyncCapability()
        capability.available = available
        return capability
    }

    @Test func focusSyncSender_focusTurnedOn_sendsOneFocusStateOn() async {
        let (sender, session) = makeSender()
        await sender.handle(focusOn: true)
        #expect(await focusStates(session) == [true])
    }

    @Test func focusSyncSender_focusUnchanged_sendsNothing() async {
        let (sender, session) = makeSender()
        await sender.handle(focusOn: true)
        await sender.handle(focusOn: true)
        #expect(await focusStates(session) == [true])
    }

    @Test func focusSyncSender_focusTurnedOffAfterOn_sendsFocusStateOff() async {
        let (sender, session) = makeSender()
        await sender.handle(focusOn: true)
        await sender.handle(focusOn: false)
        #expect(await focusStates(session) == [true, false])
    }

    @Test func focusSyncSender_capabilityUnavailable_sendsNothingUntilAvailable() async {
        let (sender, session) = makeSender()
        await sender.handle(capability: capability(available: false))
        await sender.handle(focusOn: true)
        #expect(await focusStates(session).isEmpty)
        await sender.handle(capability: capability(available: true))
        await sender.handle(focusOn: true)
        #expect(await focusStates(session) == [true])
    }

    @Test func focusSyncSender_sourceChangeAndCapabilityFrame_flowThroughStreams() async {
        let session = FakeTandemSession()
        let source = RecordingFocusStateSource()
        let sender = FocusSyncSender(source: source, session: session)
        await sender.start()
        source.emit(true)
        await settle { await focusStates(session) == [true] }
        await session.inject(
            InboundFrame(channel: .control, seq: 1, ack: 0, payload: .focusSyncCapability(capability(available: false)))
        )
        await drain()
        source.emit(false)
        await drain()
        #expect(await focusStates(session) == [true])
        await sender.stop()
    }

    private func settle(_ condition: () async -> Bool) async {
        for _ in 0..<1000 where !(await condition()) {
            await Task.yield()
        }
        #expect(await condition())
    }

    private func drain() async {
        for _ in 0..<200 {
            await Task.yield()
        }
    }
}
