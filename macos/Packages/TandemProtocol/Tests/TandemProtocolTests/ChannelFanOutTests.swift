import Foundation
import Testing
import TandemTestSupport
@testable import TandemProtocol

/// E22-12 (a): `ByteStreamSession.receive(_:)` is the one dispatch point per channel, fanning every
/// frame out to each subscriber instead of letting two readers split a single stream.
@Suite("Channel fan-out")
struct ChannelFanOutTests {
    private struct Wired {
        let sender: ByteStreamSession
        let receiver: ByteStreamSession
    }

    private static func wire() async -> Wired {
        let pair = InMemoryConnectionPair()
        let multiplexerA = ChannelMultiplexer(source: InMemoryFrameSource(pair.endA), sink: pair.endA.send)
        let multiplexerB = ChannelMultiplexer(source: InMemoryFrameSource(pair.endB), sink: pair.endB.send)
        await multiplexerA.start()
        await multiplexerB.start()
        return Wired(
            sender: ByteStreamSession(
                multiplexer: multiplexerA, stateMachine: ConnectionStateMachine(clock: ManualTestClock())
            ),
            receiver: ByteStreamSession(
                multiplexer: multiplexerB, stateMachine: ConnectionStateMachine(clock: ManualTestClock())
            )
        )
    }

    private static func collect(_ stream: InboundFrameStream, count: Int) async -> [InboundFrame] {
        var frames: [InboundFrame] = []
        for await frame in stream {
            frames.append(frame)
            if frames.count == count { break }
        }
        return frames
    }

    @Test
    func byteStreamSession_twoSubscribersOnOneChannel_eachGetsEveryFrame() async throws {
        let wired = await Self.wire()
        let first = await wired.receiver.receive(.notify)
        let second = await wired.receiver.receive(.notify)

        for index in 0..<3 {
            var dismiss = Tandem_V1_NotificationDismiss()
            dismiss.key = "k\(index)"
            try await wired.sender.send(.notify, payload: .notificationDismiss(dismiss))
        }

        let firstFrames = await Self.collect(first, count: 3)
        let secondFrames = await Self.collect(second, count: 3)
        let keys: ([String], [String]) = (
            firstFrames.compactMap { if case .notificationDismiss(let value)? = $0.payload { value.key } else { nil } },
            secondFrames.compactMap { if case .notificationDismiss(let value)? = $0.payload { value.key } else { nil } }
        )
        #expect(keys.0 == ["k0", "k1", "k2"])
        #expect(keys.1 == ["k0", "k1", "k2"])
    }

    @Test
    func byteStreamSession_close_finishesEverySubscriber() async {
        let wired = await Self.wire()
        let first = await wired.receiver.receive(.control)
        let second = await wired.receiver.receive(.control)

        await wired.receiver.close()

        var firstIterator = first.makeAsyncIterator()
        var secondIterator = second.makeAsyncIterator()
        #expect(await firstIterator.next() == nil)
        #expect(await secondIterator.next() == nil)
    }

    @Test
    func broadcast_publishBeforeFirstSubscriber_heldForFirstOnly() async {
        let broadcast = Broadcast<Int>()
        broadcast.publish(1)
        let first = broadcast.subscribe()
        let second = broadcast.subscribe()
        broadcast.publish(2)
        broadcast.finish()

        var firstValues: [Int] = []
        for await value in first { firstValues.append(value) }
        var secondValues: [Int] = []
        for await value in second { secondValues.append(value) }
        #expect(firstValues == [1, 2])
        #expect(secondValues == [2])
    }

    @Test
    func broadcast_subscribeAfterFinish_finishesImmediately() async {
        let broadcast = Broadcast<Int>()
        broadcast.finish()
        var iterator = broadcast.subscribe().makeAsyncIterator()
        #expect(await iterator.next() == nil)
    }
}
