import Foundation
import Testing
import TandemTransport

@testable import TandemApp
@testable import TandemProtocol

/// E15-16 tdd (unit): a real `ByteStreamSession` + `VersionHandshake` + `ChannelMultiplexer` over
/// the E00-25 in-memory byte stream, whose peer sends a `VersionHello` with an unsupported major,
/// surfaces the version-mismatch error through a real ``ConnectionStateRelay`` to both
/// ``MenuBarViewModel`` and ``ErrorBannerViewModel`` -- the UI half of E15-11's scenario 4, without
/// needing the accessibility tree.
@Suite("Version mismatch reaches the menu bar")
struct VersionMismatchMenuTests {
    @Test
    func mitmLab_helloUnsupportedMajorVersion_menuShowsVersionError() async throws {
        let pair = InMemoryConnectionPair()
        let clock = ManualTestClock()
        let multiplexer = ChannelMultiplexer(source: EndFrameSource(pair.endA), sink: pair.endA.send)
        let stateMachine = ConnectionStateMachine(clock: clock)
        let handshake = VersionHandshake(multiplexer: multiplexer, clock: clock)
        let session = ByteStreamSession(multiplexer: multiplexer, stateMachine: stateMachine)

        let relay = ConnectionStateRelay()
        let menuBar = await MenuBarViewModel(stateStream: relay.makeStream(), peerName: "Pixel 8")
        let banner = await ErrorBannerViewModel(stateStream: relay.makeStream(), peerName: "Pixel 8")
        await relay.attach(session)

        await stateMachine.handle(.incomingConnection)
        await stateMachine.handle(.handshakeStarted)
        await stateMachine.handle(.handshakeCompleted)
        await multiplexer.start()
        let runTask = Task { await handshake.run() }
        try await sendPeerHello(major: 99, over: pair.endB)
        await runTask.value
        #expect(await handshake.session == .failed(.versionMismatch))
        await stateMachine.handle(.handshakeError(.versionMismatch))

        var attempts = 0
        while attempts < 10_000 {
            let bannerMessage = await banner.message
            let menuState = await menuBar.state
            if bannerMessage != nil, menuState == .error { break }
            await Task.yield()
            attempts += 1
        }

        #expect(await menuBar.state == .error)
        #expect(await banner.message == "Pixel 8 runs an incompatible Tandem version. Update both apps.")
    }

    @Test
    func connectionStateRelay_streamCreatedAfterFailure_startsWithLatestState() async throws {
        let relay = ConnectionStateRelay()
        let session = FakeTandemSession()
        await relay.attach(session)
        await session.emit(.failed(.versionMismatch))

        var earlySubscriber = relay.makeStream().makeAsyncIterator()
        while await earlySubscriber.next() != .failed(.versionMismatch) {}

        var lateSubscriber = relay.makeStream().makeAsyncIterator()
        let received = await lateSubscriber.next()

        #expect(received == .failed(.versionMismatch))
    }

    private func sendPeerHello(major: UInt32, over end: InMemoryConnectionPair.End) async throws {
        var hello = Tandem_V1_VersionHello()
        hello.major = major
        var envelope = Tandem_V1_Envelope()
        envelope.channel = .control
        envelope.seq = 1
        envelope.payload = .versionHello(hello)
        try await end.send(try FrameEncoder.encode(envelope))
    }
}

/// Adapts an in-memory end's `receive()` to `FrameSource` -- the same shape as
/// `TandemProtocolTests`' own `InMemoryFrameSource`, which this target can't import.
private final class EndFrameSource: FrameSource, @unchecked Sendable {
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
