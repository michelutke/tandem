import CoreGraphics
import Foundation
import Testing
@testable import TandemProtocol
@testable import FeatureMirror

private let sessionId = Data(repeating: 9, count: 16)

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
@Test func mirrorInputSender_activeSession_sendsInputEventOnInputChannel() async {
    let session = FakeTandemSession()
    let sender = makeSender(session: session)
    sender.handle(.pressed(point: CGPoint(x: 10, y: 10), time: 0))
    sender.handle(.released(point: CGPoint(x: 10, y: 10), time: 0.01))
    await sender.drain()
    let sent = await session.sent
    #expect(sent.count == 1)
    #expect(sent[0].channel == .input)
    guard case .inputEvent(let event) = sent[0].payload else {
        Issue.record("expected inputEvent")
        return
    }
    #expect(event.sessionID == sessionId)
}

@MainActor
@Test func mirrorInputSender_afterStop_sendsNothing() async {
    let session = FakeTandemSession()
    let sender = makeSender(session: session)
    sender.stop()
    sender.handle(.scrolled(point: CGPoint(x: 10, y: 10), deltaX: 0, deltaY: 3, time: 0))
    await sender.drain()
    #expect(await session.sent.isEmpty)
}

@MainActor
@Test func mirrorInputSender_controlSessionFails_sendsNothing() async {
    let session = FakeTandemSession()
    let sender = makeSender(session: session)
    await session.emit(.failed(.malformedFrame))
    for _ in 0..<1000 where sender.isActive { await Task.yield() }
    #expect(!sender.isActive)
    sender.handle(.scrolled(point: CGPoint(x: 10, y: 10), deltaX: 0, deltaY: 3, time: 0))
    await sender.drain()
    #expect(await session.sent.isEmpty)
}
