import CoreGraphics
import Foundation
import Testing
@testable import TandemProtocol
@testable import FeatureMirror

private let sessionId = Data(repeating: 5, count: 16)

@MainActor
private func makeSender(session: FakeTandemSession) -> MirrorInputSender {
    let model = MirrorWindowModel(
        streamSize: CGSize(width: 1000, height: 1000), windowSize: CGSize(width: 1000, height: 1000))
    guard let sender = MirrorInputSender(session: session, sessionId: sessionId, model: model) else {
        fatalError("valid session id")
    }
    sender.setWindowKey(true)
    return sender
}

@MainActor
@Suite("MirrorToolbarModel")
struct MirrorToolbarModelTests {
    @Test
    func mirrorToolbar_senderPresent_controlIsOn() {
        let sender = makeSender(session: FakeTandemSession())
        let toolbar = MirrorToolbarModel(inputSender: sender, onStop: {})
        #expect(toolbar.isControlOn)
    }

    @Test
    func mirrorToolbar_noSender_controlIsOffAndHomeSendsNothing() async {
        let toolbar = MirrorToolbarModel(inputSender: nil, onStop: {})
        toolbar.perform(.home)
        #expect(!toolbar.isControlOn)
    }

    @Test
    func mirrorToolbar_senderStopped_controlIsOff() {
        let sender = makeSender(session: FakeTandemSession())
        let toolbar = MirrorToolbarModel(inputSender: sender, onStop: {})
        sender.stop()
        #expect(!toolbar.isControlOn)
    }

    @Test(arguments: [
        (MirrorGlobalAction.back, Tandem_V1_GlobalActionKind.back),
        (MirrorGlobalAction.recents, Tandem_V1_GlobalActionKind.recents)
    ])
    func mirrorToolbar_buttonPressed_sendsGlobalActionOnInputChannel(
        action: MirrorGlobalAction, kind: Tandem_V1_GlobalActionKind
    ) async {
        let session = FakeTandemSession()
        let sender = makeSender(session: session)
        let toolbar = MirrorToolbarModel(inputSender: sender, onStop: {})

        toolbar.perform(action)
        await sender.drain()

        let sent = await session.sent
        #expect(sent.count == 1)
        #expect(sent[0].channel == .input)
        guard case .inputEvent(let event) = sent[0].payload else {
            Issue.record("expected inputEvent")
            return
        }
        #expect(event.sessionID == sessionId)
        #expect(event.globalAction.action == kind)
    }

    @Test
    func mirrorToolbar_afterSenderStopped_buttonSendsNothing() async {
        let session = FakeTandemSession()
        let sender = makeSender(session: session)
        let toolbar = MirrorToolbarModel(inputSender: sender, onStop: {})
        sender.stop()

        toolbar.perform(.back)
        await sender.drain()

        #expect(await session.sent.isEmpty)
    }

    @Test
    func mirrorToolbar_windowNotKey_buttonSendsNothing() async {
        let session = FakeTandemSession()
        let sender = makeSender(session: session)
        sender.setWindowKey(false)
        let toolbar = MirrorToolbarModel(inputSender: sender, onStop: {})

        toolbar.perform(.home)
        await sender.drain()

        #expect(await session.sent.isEmpty)
    }

    @Test
    func mirrorToolbar_stopPressed_callsOnStopOnce() {
        var stops = 0
        let toolbar = MirrorToolbarModel(inputSender: nil, onStop: { stops += 1 })

        toolbar.stop()

        #expect(stops == 1)
    }
}
