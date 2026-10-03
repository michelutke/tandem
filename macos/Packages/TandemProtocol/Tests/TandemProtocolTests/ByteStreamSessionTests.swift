import Foundation
import Testing
import TandemTestSupport
@testable import TandemProtocol

/// E12-12: `ByteStreamSession`, the ``TandemSession`` composing a ``ChannelMultiplexer`` (E11-08)
/// with a ``ConnectionStateMachine`` (E12-09) over `InMemoryConnectionPair` (E00-25), adapting
/// inbound bytes via `InMemoryFrameSource` exactly as `ChannelMultiplexerTests` already does.
@Suite("ByteStreamSession")
struct ByteStreamSessionTests {
    @Test
    func byteStreamSession_notifySendOverPair_peerReceivesIdenticalEnvelope() async throws {
        let pair = InMemoryConnectionPair()
        let multiplexerA = ChannelMultiplexer(source: InMemoryFrameSource(pair.endA), sink: pair.endA.send)
        let multiplexerB = ChannelMultiplexer(source: InMemoryFrameSource(pair.endB), sink: pair.endB.send)
        await multiplexerA.start()
        await multiplexerB.start()

        let sessionA = ByteStreamSession(
            multiplexer: multiplexerA, stateMachine: ConnectionStateMachine(clock: ManualTestClock())
        )
        let sessionB = ByteStreamSession(
            multiplexer: multiplexerB, stateMachine: ConnectionStateMachine(clock: ManualTestClock())
        )

        let heartbeat = Tandem_V1_Heartbeat()

        let notifyStream = await sessionB.receive(.notify)
        try await sessionA.send(.notify, payload: .heartbeat(heartbeat))

        var iterator = notifyStream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received?.channel == .notify)
        #expect(received?.payload == .heartbeat(heartbeat))
    }

    @Test
    func byteStreamSession_close_stateDisconnectedAndReceiveFinishes() async throws {
        let pair = InMemoryConnectionPair()
        let multiplexer = ChannelMultiplexer(source: InMemoryFrameSource(pair.endA), sink: pair.endA.send)
        await multiplexer.start()

        let stateMachine = ConnectionStateMachine(clock: ManualTestClock())
        _ = await stateMachine.handle(.incomingConnection)
        _ = await stateMachine.handle(.handshakeStarted)
        _ = await stateMachine.handle(.handshakeCompleted)
        _ = await stateMachine.handle(.compatibleHelloReceived)

        let session = ByteStreamSession(multiplexer: multiplexer, stateMachine: stateMachine)
        let notifyStream = await session.receive(.notify)

        await session.close()

        let finalState = await stateMachine.state
        #expect(finalState == .disconnected(reason: "closed locally"))

        var iterator = notifyStream.makeAsyncIterator()
        let next = await iterator.next()
        #expect(next == nil)
    }

    @Test
    func byteStreamSession_closeWithStalledSubscriber_allSubscriberStreamsFinish() async throws {
        let pair = InMemoryConnectionPair()
        let multiplexerA = ChannelMultiplexer(source: InMemoryFrameSource(pair.endA), sink: pair.endA.send)
        let multiplexerB = ChannelMultiplexer(source: InMemoryFrameSource(pair.endB), sink: pair.endB.send)
        await multiplexerA.start()
        await multiplexerB.start()
        let sender = ByteStreamSession(
            multiplexer: multiplexerA, stateMachine: ConnectionStateMachine(clock: ManualTestClock())
        )
        let session = ByteStreamSession(
            multiplexer: multiplexerB, stateMachine: ConnectionStateMachine(clock: ManualTestClock())
        )

        let stalled = await session.receive(.notify)
        let consuming = await session.receive(.notify)
        let consumer = Task { for await _ in consuming {} }
        for _ in 0..<(ByteStreamSession.fanOutWindow + 2) {
            try await sender.send(.notify, payload: .heartbeat(Tandem_V1_Heartbeat()))
        }
        try await Task.sleep(for: .milliseconds(200))

        await session.close()

        await consumer.value
        var iterator = stalled.makeAsyncIterator()
        var drained = 0
        while await iterator.next() != nil { drained += 1 }
        #expect(drained >= ByteStreamSession.fanOutWindow)
    }
}
