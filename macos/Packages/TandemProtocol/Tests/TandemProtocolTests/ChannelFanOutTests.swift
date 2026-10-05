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
        let receiverMultiplexer: ChannelMultiplexer
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
            ),
            receiverMultiplexer: multiplexerB
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

    @Test
    func byteStreamSession_subscriberNotConsuming_readerStopsAfterWindowAndCreditStalls() async throws {
        let wired = await Self.wire()
        let stalled = await wired.receiver.receive(.notify)
        let total = ByteStreamSession.fanOutWindow * 3
        for index in 0..<total {
            var dismiss = Tandem_V1_NotificationDismiss()
            dismiss.key = "k\(index)"
            try await wired.sender.send(.notify, payload: .notificationDismiss(dismiss))
        }
        let window = UInt32(ByteStreamSession.fanOutWindow)
        var pulled: UInt32 = 0
        for _ in 0..<10_000 where pulled < window {
            await Task.yield()
            pulled = await wired.receiverMultiplexer.consumedSinceLastGrant[.notify] ?? 0
        }
        for _ in 0..<2_000 { await Task.yield() }
        pulled = await wired.receiverMultiplexer.consumedSinceLastGrant[.notify] ?? 0
        #expect(pulled == window)

        var iterator = stalled.makeAsyncIterator()
        for _ in 0..<total { _ = await iterator.next() }
        let drained = await wired.receiverMultiplexer.consumedSinceLastGrant[.notify] ?? 0
        #expect(drained == UInt32(total))
    }

    @Test
    func broadcast_subscribeAfterHeld_replaysInOrderBeforeLaterPublishes() async {
        let broadcast = Broadcast<Int>()
        for value in 0..<50 { broadcast.publish(value) }
        let stream = broadcast.subscribe()
        for value in 50..<100 { broadcast.publish(value) }
        broadcast.finish()
        var values: [Int] = []
        for await value in stream { values.append(value) }
        #expect(values == Array(0..<100))
    }

    @Test
    func broadcast_replayUntilSealed_lateSubscribersBeforeSealSeeEveryElement() async {
        let broadcast = Broadcast<Int>(replayUntilSealed: true)
        let first = broadcast.subscribe()
        broadcast.publish(1)
        let second = broadcast.subscribe()
        broadcast.publish(2)
        broadcast.seal()
        let third = broadcast.subscribe()
        broadcast.publish(3)
        broadcast.finish()
        var firstValues: [Int] = []
        for await value in first { firstValues.append(value) }
        var secondValues: [Int] = []
        for await value in second { secondValues.append(value) }
        var thirdValues: [Int] = []
        for await value in third { thirdValues.append(value) }
        #expect(firstValues == [1, 2, 3])
        #expect(secondValues == [1, 2, 3])
        #expect(thirdValues == [3])
    }

    @Test
    func broadcast_replayUntilSealed_sealBeforeAnySubscriber_firstSubscriberStillGetsHeld() async {
        let broadcast = Broadcast<Int>(replayUntilSealed: true)
        broadcast.publish(1)
        broadcast.seal()
        let first = broadcast.subscribe()
        broadcast.publish(2)
        let second = broadcast.subscribe()
        broadcast.finish()
        var firstValues: [Int] = []
        for await value in first { firstValues.append(value) }
        var secondValues: [Int] = []
        for await value in second { secondValues.append(value) }
        #expect(firstValues == [1, 2])
        #expect(secondValues.isEmpty)
    }
}
