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

    @Test
    func multiplexer_concurrentSendsOnSameChannel_reachWireInCallOrder() async throws {
        let pair = InMemoryConnectionPair()
        let sink = ControllableSink(forward: pair.endA.send)
        let sender = ChannelMultiplexer(source: InMemoryFrameSource(pair.endA), sink: sink.write)

        // Task 1 assigns seq 1 and suspends inside the sink (the write hasn't reached the wire
        // yet). If `send` were reentrant across that suspension (Swift actors are, by default),
        // Task 2 could assign seq 2 and complete its own write first, reordering the wire.
        let firstSend = Task { try await sender.send(.notify, payload: .heartbeat(Tandem_V1_Heartbeat())) }
        await sink.waitUntilFirstWriteStarted()

        let secondSend = Task { try await sender.send(.notify, payload: .heartbeat(Tandem_V1_Heartbeat())) }
        // Give Task 2 every opportunity to race ahead of Task 1 before releasing the first write;
        // there is nothing else to synchronize on since the whole point under test is that it
        // cannot make progress past the write lock while Task 1 holds it.
        await Task.yield()
        await Task.yield()

        await sink.releaseFirstWrite()
        try await firstSend.value
        try await secondSend.value

        let wire = InMemoryFrameSource(pair.endB)
        var seqs: [UInt64] = []
        for _ in 0..<2 {
            guard case .frame(let envelope)? = try await FrameDecoder.decode(from: wire) else {
                Issue.record("expected a decodable frame")
                return
            }
            seqs.append(envelope.seq)
        }
        #expect(seqs == [1, 2], "bytes must reach the wire in call order, not just seq order")
    }

    @Test
    func multiplexer_seqGapExceedsProtocolMax_closesWithSeqGapTooLarge() async throws {
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

        let protocolMax = Int(CreditCaps.protocolMax)
        // Never sends seq 1, so every one of these stays pending above the watermark (a
        // legitimate gap-fill per D-57) until the pending set holds exactly `protocolMax` entries
        // (seq 2...protocolMax+1).
        for seq in 2...(protocolMax + 1) {
            try await sendFromPeer(seq: UInt64(seq))
            let routed = await notifyIterator.next()
            #expect(routed?.seq == UInt64(seq))
        }

        // One more above-watermark seq would push the pending set past `protocolMax`: no
        // legitimate, credit-bound peer can reach this (D-64), so it is fatal.
        try await sendFromPeer(seq: UInt64(protocolMax + 2))

        let next = await notifyIterator.next()
        #expect(next == nil, "the stream must finish, not yield a frame, for the violating send")

        let closeReason = await receiver.closeReason
        #expect(closeReason == .violation(.malformedFrame, .seqGapTooLarge))
    }
}

/// A hand-rolled ``ChannelMultiplexer/OutboundSink`` that suspends its *first* call until
/// ``releaseFirstWrite()`` is invoked, then forwards every call (including that first one, once
/// released) to `forward` in the order `write(_:)` was called. Used to force two concurrent
/// `ChannelMultiplexer.send(_:payload:)` calls to interleave at the exact point findings 1–2
/// describe: one call suspended mid-write while another tries to start.
actor ControllableSink {
    private let forward: @Sendable (Data) async throws -> Void
    private var isFirstCall = true
    private var firstCallStarted = false
    private var firstCallStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(forward: @escaping @Sendable (Data) async throws -> Void) {
        self.forward = forward
    }

    func write(_ data: Data) async throws {
        if isFirstCall {
            isFirstCall = false
            firstCallStarted = true
            let waiters = firstCallStartedWaiters
            firstCallStartedWaiters = []
            for waiter in waiters { waiter.resume() }
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
        try await forward(data)
    }

    /// Suspends until the first `write(_:)` call has started (and is now suspended waiting for
    /// ``releaseFirstWrite()``), so a caller can be sure that call has already assigned its `seq`
    /// before racing a second one against it.
    func waitUntilFirstWriteStarted() async {
        if firstCallStarted { return }
        await withCheckedContinuation { continuation in
            firstCallStartedWaiters.append(continuation)
        }
    }

    func releaseFirstWrite() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
