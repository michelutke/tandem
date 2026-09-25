import Foundation
import Testing
import TandemTestSupport
@testable import TandemProtocol

/// E11-06: Swift `ChannelMultiplexer`, the macOS counterpart to Android's `ChannelMultiplexer`
/// (E11-05). Wires two multiplexers (or a multiplexer against a hand-built peer) over an
/// `InMemoryConnectionPair` (E00-25), adapting inbound bytes to `FrameSource` via
/// `InMemoryFrameSource` since `TandemProtocol` may not depend on `TandemTransport` (see
/// `ChannelMultiplexer`'s own doc comment and this package's `Package.swift`). A
/// `ByteStreamConnection.send(_:)` already matches the outbound sink signature, so `pair.endX.send`
/// is passed directly with no adapter.
@Suite("ChannelMultiplexer")
struct ChannelMultiplexerTests {
    @Test
    func multiplexer_frameOnNotify_notYieldedOnAnyOtherChannelStream() async throws {
        let pair = InMemoryConnectionPair()
        let sender = ChannelMultiplexer(source: InMemoryFrameSource(pair.endA), sink: pair.endA.send)
        let receiver = ChannelMultiplexer(source: InMemoryFrameSource(pair.endB), sink: pair.endB.send)
        await sender.start()
        await receiver.start()

        let notifyStream = await receiver.inbound(.notify)
        let filesStream = await receiver.inbound(.files)

        try await sender.send(.notify, payload: .heartbeat(Tandem_V1_Heartbeat()))
        try await sender.send(.files, payload: .creditGrant(Tandem_V1_CreditGrant()))

        var filesIterator = filesStream.makeAsyncIterator()
        let filesFrame = await filesIterator.next()
        #expect(filesFrame?.channel == .files)
        guard case .creditGrant? = filesFrame?.payload else {
            Issue.record("FILES stream did not yield the FILES frame: \(String(describing: filesFrame))")
            return
        }

        var notifyIterator = notifyStream.makeAsyncIterator()
        let notifyFrame = await notifyIterator.next()
        #expect(notifyFrame?.channel == .notify)
        guard case .heartbeat? = notifyFrame?.payload else {
            Issue.record("NOTIFY stream did not yield the NOTIFY frame: \(String(describing: notifyFrame))")
            return
        }
    }

    @Test
    func multiplexer_sendsOnTwoChannels_seqCountsIndependentlyFromOne() async throws {
        let pair = InMemoryConnectionPair()
        let sender = ChannelMultiplexer(source: InMemoryFrameSource(pair.endA), sink: pair.endA.send)

        try await sender.send(.notify, payload: .heartbeat(Tandem_V1_Heartbeat()))
        try await sender.send(.files, payload: .creditGrant(Tandem_V1_CreditGrant()))
        try await sender.send(.notify, payload: .heartbeat(Tandem_V1_Heartbeat()))
        try await sender.send(.notify, payload: .heartbeat(Tandem_V1_Heartbeat()))

        let wire = InMemoryFrameSource(pair.endB)
        var channels: [Tandem_V1_Channel] = []
        var seqs: [UInt64] = []
        for _ in 0..<4 {
            guard case .frame(let envelope)? = try await FrameDecoder.decode(from: wire) else {
                Issue.record("expected a decodable frame")
                return
            }
            channels.append(envelope.channel)
            seqs.append(envelope.seq)
        }

        #expect(channels == [.notify, .files, .notify, .notify])
        #expect(seqs == [1, 1, 2, 3])
    }

    @Test
    func multiplexer_receivedSeq1And3_ackIs1UntilSeq2Arrives() async throws {
        let pair = InMemoryConnectionPair()
        let receiver = ChannelMultiplexer(source: InMemoryFrameSource(pair.endB), sink: pair.endB.send)
        await receiver.start()

        let notifyStream = await receiver.inbound(.notify)
        var notifyIterator = notifyStream.makeAsyncIterator()
        let peerWire = InMemoryFrameSource(pair.endA)

        func sendFromPeer(seq: UInt64) async throws {
            var envelope = Tandem_V1_Envelope()
            envelope.channel = .notify
            envelope.seq = seq
            envelope.payload = .heartbeat(Tandem_V1_Heartbeat())
            try await pair.endA.send(try FrameEncoder.encode(envelope))
            _ = await notifyIterator.next() // synchronize: wait until the receiver has routed it
        }

        func currentAck() async throws -> UInt64 {
            try await receiver.send(.notify, payload: .heartbeat(Tandem_V1_Heartbeat()))
            guard case .frame(let envelope)? = try await FrameDecoder.decode(from: peerWire) else {
                Issue.record("expected a decodable outbound frame")
                return 0
            }
            return envelope.ack
        }

        try await sendFromPeer(seq: 1)
        #expect(try await currentAck() == 1)

        try await sendFromPeer(seq: 3)
        #expect(try await currentAck() == 1)

        try await sendFromPeer(seq: 2)
        #expect(try await currentAck() == 3)
    }

    @Test
    func multiplexer_regressingIncomingSeq_appliesSpecDefinedOutcome() async throws {
        let pair = InMemoryConnectionPair()
        let receiver = ChannelMultiplexer(source: InMemoryFrameSource(pair.endB), sink: pair.endB.send)
        await receiver.start()

        let notifyStream = await receiver.inbound(.notify)
        var notifyIterator = notifyStream.makeAsyncIterator()

        func sendFromPeer(seq: UInt64) async throws {
            var envelope = Tandem_V1_Envelope()
            envelope.channel = .notify
            envelope.seq = seq
            envelope.payload = .heartbeat(Tandem_V1_Heartbeat())
            try await pair.endA.send(try FrameEncoder.encode(envelope))
        }

        try await sendFromPeer(seq: 1)
        let first = await notifyIterator.next()
        #expect(first?.seq == 1)

        // Repeats a value already at the watermark (1 <= 1): SPEC.md #framing-and-envelope
        // "Sequence and acknowledgement violations", D-57.
        try await sendFromPeer(seq: 1)

        let next = await notifyIterator.next()
        #expect(next == nil, "the stream must finish, not yield a frame, for the violating send")

        let closeReason = await receiver.closeReason
        #expect(closeReason == .violation(.malformedFrame, .seqRegression))
    }
}
