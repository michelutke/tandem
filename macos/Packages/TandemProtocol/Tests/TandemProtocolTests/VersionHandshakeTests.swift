import Foundation
import Testing
import TandemTestSupport
@testable import TandemProtocol

/// E12-07: `VersionHandshake` (Android counterpart: `VersionHandshake`, E12-15), the version/
/// capability handshake over the CONTROL channel (docs/protocol/SPEC.md
/// #versioning-and-capability-negotiation; `docs/planning/decisions.md` D-63). Drives a real
/// `ChannelMultiplexer` (E11-06/E11-08) against a scripted peer over `InMemoryConnectionPair`
/// (E00-25), same wiring as `ChannelMultiplexerTests`.
@Suite("VersionHandshake")
struct VersionHandshakeTests {
    @Test
    func hello_peerSameMajorHigherMinor_stateBecomesReady() async throws {
        let pair = InMemoryConnectionPair()
        let multiplexer = ChannelMultiplexer(source: InMemoryFrameSource(pair.endA), sink: pair.endA.send)
        await multiplexer.start()
        let handshake = VersionHandshake(multiplexer: multiplexer, clock: ManualTestClock())

        let runTask = Task { await handshake.run() }
        try await sendPeerHello(major: 1, minor: 5, capabilities: 0, over: pair.endB)
        await runTask.value

        let session = await handshake.session
        #expect(session == .ready(peerCapabilities: 0))
    }

    @Test
    func hello_peerDifferentMajor_closesVersionMismatchAndFailedState() async throws {
        let pair = InMemoryConnectionPair()
        let multiplexer = ChannelMultiplexer(source: InMemoryFrameSource(pair.endA), sink: pair.endA.send)
        await multiplexer.start()
        let handshake = VersionHandshake(multiplexer: multiplexer, clock: ManualTestClock())

        let runTask = Task { await handshake.run() }
        try await sendPeerHello(major: 2, minor: 0, capabilities: 0, over: pair.endB)
        await runTask.value

        let session = await handshake.session
        #expect(session == .failed(.versionMismatch))
    }

    @Test
    func hello_notifySendBeforePeerHello_zeroNotifyBytesOnWire() async throws {
        let pair = InMemoryConnectionPair()
        let multiplexer = ChannelMultiplexer(source: InMemoryFrameSource(pair.endA), sink: pair.endA.send)
        await multiplexer.start()
        let handshake = VersionHandshake(multiplexer: multiplexer, clock: ManualTestClock())

        let runTask = Task { await handshake.run() }
        let notifyTask = Task { try await handshake.send(.notify, payload: .heartbeat(Tandem_V1_Heartbeat())) }
        for _ in 0..<10 { await Task.yield() } // let the NOTIFY send finish enqueuing behind the gate

        let channelsBeforeHello = try await decodedChannels(from: pair.captured(.aToB))
        #expect(!channelsBeforeHello.contains(.notify), "no NOTIFY bytes may reach the wire before Ready")

        try await sendPeerHello(major: 1, minor: 0, capabilities: 0, over: pair.endB)
        await runTask.value
        try await notifyTask.value

        let channelsAfterHello = try await decodedChannels(from: pair.captured(.aToB))
        #expect(channelsAfterHello.contains(.notify), "the gated NOTIFY send must reach the wire once Ready")
    }

    @Test
    func hello_peerUnknownCapabilityBit_ignoredAndOthersExposed() async throws {
        let pair = InMemoryConnectionPair()
        let multiplexer = ChannelMultiplexer(source: InMemoryFrameSource(pair.endA), sink: pair.endA.send)
        await multiplexer.start()
        let handshake = VersionHandshake(multiplexer: multiplexer, clock: ManualTestClock())

        // Bit 63 is unassigned in this protocol version (SPEC.md "Capability mismatch": no bit
        // has meaning yet) but MUST still be exposed on the raw value, never filtered out.
        let unknownBit: UInt64 = 1 << 63
        let runTask = Task { await handshake.run() }
        try await sendPeerHello(major: 1, minor: 0, capabilities: unknownBit, over: pair.endB)
        await runTask.value

        let session = await handshake.session
        #expect(session == .ready(peerCapabilities: unknownBit))
    }

    @Test
    func hello_noPeerHelloWithin5s_closesProtocolTimeout() async throws {
        let pair = InMemoryConnectionPair()
        let multiplexer = ChannelMultiplexer(source: InMemoryFrameSource(pair.endA), sink: pair.endA.send)
        await multiplexer.start()
        let clock = ManualTestClock()
        let handshake = VersionHandshake(multiplexer: multiplexer, clock: clock)

        let runTask = Task { await handshake.run() }
        for _ in 0..<10 { await Task.yield() } // let run() send its own hello and start racing the deadline
        clock.advance(by: .seconds(5))
        await runTask.value

        let session = await handshake.session
        #expect(session == .failed(.protocolTimeout))
    }

    private func sendPeerHello(
        major: UInt32, minor: UInt32, capabilities: UInt64, over end: InMemoryConnectionPair.End
    ) async throws {
        var hello = Tandem_V1_VersionHello()
        hello.major = major
        hello.minor = minor
        hello.capabilities = capabilities
        var envelope = Tandem_V1_Envelope()
        envelope.channel = .control
        envelope.seq = 1
        envelope.payload = .versionHello(hello)
        try await end.send(try FrameEncoder.encode(envelope))
    }

    private func decodedChannels(from data: Data) async throws -> [Tandem_V1_Channel] {
        let source = ReplayFrameSource(data)
        var channels: [Tandem_V1_Channel] = []
        while case .frame(let envelope)? = try await FrameDecoder.decode(from: source) {
            channels.append(envelope.channel)
        }
        return channels
    }
}

/// Decodes frames out of an already-captured, frame-aligned byte buffer (``InMemoryConnectionPair
/// /captured(_:)``) rather than a live stream: never suspends, since there is nothing more to
/// arrive -- reads exactly what is left, treating running out early as a clean close, matching
/// ``FrameSource/read(exactly:)``'s own contract.
final class ReplayFrameSource: FrameSource, @unchecked Sendable {
    private var remaining: Data

    init(_ data: Data) {
        remaining = data
    }

    func read(exactly count: Int) async throws -> Data {
        let chunk = remaining.prefix(count)
        remaining.removeFirst(chunk.count)
        return Data(chunk)
    }
}
