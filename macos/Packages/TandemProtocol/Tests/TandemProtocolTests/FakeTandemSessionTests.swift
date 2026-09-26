import Foundation
import Testing
@testable import TandemProtocol

/// E12-12: `FakeTandemSession`, the ``TandemSession`` test double used by feature tests (and the
/// DEBUG-only E00-26 scenario seeding) instead of a real ``ByteStreamSession``.
@Suite("FakeTandemSession")
struct FakeTandemSessionTests {
    @Test
    func fakeTandemSession_sendCalls_recordedInOrder() async throws {
        let session = FakeTandemSession()

        try await session.send(.notify, payload: .heartbeat(Tandem_V1_Heartbeat()))
        try await session.send(.files, payload: .creditGrant(Tandem_V1_CreditGrant()))

        let sent = await session.sent
        #expect(sent.map(\.channel) == [.notify, .files])
        #expect(sent[0].payload == .heartbeat(Tandem_V1_Heartbeat()))
        #expect(sent[1].payload == .creditGrant(Tandem_V1_CreditGrant()))
    }

    @Test
    func fakeTandemSession_injectedIncomingFrame_yieldedOnReceiveStream() async throws {
        let session = FakeTandemSession()

        let stream = await session.receive(.notify)
        let frame = InboundFrame(channel: .notify, seq: 1, ack: 0, payload: .heartbeat(Tandem_V1_Heartbeat()))
        await session.inject(frame)

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received == frame)
    }
}
