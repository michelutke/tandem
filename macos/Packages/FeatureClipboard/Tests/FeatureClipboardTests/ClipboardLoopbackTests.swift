import AppKit
import Foundation
import Testing
@testable import FeatureClipboard
@testable import TandemProtocol
@testable import TandemTestSupport

/// Adapts an `InMemoryConnectionPair.End`'s `receive()` (E00-25) to ``FrameSource`` (E11-04),
/// mirroring `TandemProtocolTests`' own `InMemoryFrameSource` -- duplicated here rather than
/// shared since that adapter is private to `TandemProtocolTests` (`TandemProtocol` may not depend
/// on `TandemTransport`, so this lives in test code either way).
private final class LoopbackFrameSource: FrameSource, @unchecked Sendable {
    private var iterator: AsyncThrowingStream<Data, Error>.AsyncIterator
    private var buffer = Data()

    init(_ end: InMemoryConnectionPair.End) {
        iterator = end.receive().makeAsyncIterator()
    }

    func read(exactly count: Int) async throws -> Data {
        while buffer.count < count {
            guard let chunk = try await iterator.next() else {
                let collected = buffer
                buffer.removeAll()
                return collected
            }
            buffer.append(chunk)
        }
        let result = Data(buffer.prefix(count))
        buffer.removeFirst(count)
        return result
    }
}

/// Records every frame a test peer's own inbound stream yields, off the actor under test, so a
/// test can assert on it after driving virtual time forward.
private actor FrameCollector {
    private(set) var frames: [InboundFrame] = []

    func record(_ frame: InboundFrame) {
        frames.append(frame)
    }
}

/// E31-14 (also feeds E31-10's own loopback acceptance): wires the real ``ClipboardSender``
/// (E31-04) and ``PasteboardWriter`` (E31-13) -- sharing one ``ClipboardLoopGuard`` -- to a real
/// ``ByteStreamSession`` over an ``InMemoryConnectionPair`` (E00-25), against a test peer that is
/// a second, bare ``ChannelMultiplexer`` on the other end. Proves the whole receive-then-poll-
/// detects-then-skip loop closes end to end, not just at the unit level.
@Suite("Clipboard loopback", .serialized)
struct ClipboardLoopbackTests {
    @Test
    func clipboardLoopback_peerSendsOneClip_zeroClipboardFramesEchoedIn5s() async throws {
        let clock = ManualTestClock()
        let pair = InMemoryConnectionPair()

        let macMultiplexer = ChannelMultiplexer(source: LoopbackFrameSource(pair.endA), sink: pair.endA.send)
        let macSession = ByteStreamSession(
            multiplexer: macMultiplexer,
            stateMachine: ConnectionStateMachine(clock: clock)
        )
        await macMultiplexer.start()

        let peerMultiplexer = ChannelMultiplexer(source: LoopbackFrameSource(pair.endB), sink: pair.endB.send)
        await peerMultiplexer.start()

        let source = FakePasteboardSource(changeCount: 0, types: [.string])
        let loopGuard = ClipboardLoopGuard()
        let sender = ClipboardSender(source: source, clock: clock, session: macSession, loopGuard: loopGuard)
        let writer = PasteboardWriter(source: source, session: macSession, loopGuard: loopGuard)
        await sender.start()
        await writer.start()
        #expect(await waitForParkedSleepers(clock, count: 1))

        let collector = FrameCollector()
        let collectTask = Task {
            for await frame in await peerMultiplexer.inbound(.clipboard) {
                await collector.record(frame)
            }
        }

        var clipboardText = Tandem_V1_ClipboardText()
        clipboardText.originTag = "android"
        clipboardText.text = "loopback canary"
        try await peerMultiplexer.send(.clipboard, payload: .clipboardText(clipboardText))

        let wrote = await waitUntilTrue { source.string(forType: .string) == "loopback canary" }
        #expect(wrote)
        await realDelay(milliseconds: 20)

        // 20 poll ticks at the 250ms poll interval == 5s of virtual time.
        for _ in 0..<20 {
            #expect(await waitForParkedSleepers(clock, count: 1))
            clock.advance(by: PasteboardPoller.pollInterval)
        }
        await realDelay(milliseconds: 20)

        #expect(await collector.frames.isEmpty, "the peer must receive zero CLIPBOARD frames echoed back")

        collectTask.cancel()
        await sender.stop()
        await writer.stop()
    }
}
