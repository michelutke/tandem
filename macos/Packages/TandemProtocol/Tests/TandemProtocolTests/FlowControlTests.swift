import Foundation
import Synchronization
import Testing
import TandemTestSupport
@testable import TandemProtocol

/// E11-08: wires ``CreditLedger`` (E11-14) into ``ChannelMultiplexer`` (E11-06) -- suspending
/// per-channel sends, the fair round-robin frame writer, and receive-side credit grants
/// (docs/protocol/SPEC.md #channels-and-flow-control-credits; `docs/planning/decisions.md` D-64).
@Suite("FlowControl")
struct FlowControlTests {
    @Test
    func flowControl_zeroCredit_sendSuspendedUntilGrantDelivered() async throws {
        let pair = InMemoryConnectionPair()
        let sender = ChannelMultiplexer(source: InMemoryFrameSource(pair.endA), sink: pair.endA.send)
        await sender.start()

        let cap = CreditCaps.capFor(.files)
        for _ in 0..<cap {
            try await sender.send(.files, payload: .heartbeat(Tandem_V1_Heartbeat()))
        }

        let completed = Mutex(false)
        let pendingSend = Task {
            try await sender.send(.files, payload: .heartbeat(Tandem_V1_Heartbeat()))
            completed.withLock { $0 = true }
        }

        for _ in 0..<5 { await Task.yield() }
        #expect(completed.withLock { $0 } == false, "send must suspend while FILES credit is exhausted")

        let clock = ManualTestClock()
        clock.advance(by: .seconds(10))
        for _ in 0..<5 { await Task.yield() }
        #expect(completed.withLock { $0 } == false, "advancing an unrelated clock must not resolve a credit-gated send")

        var grant = Tandem_V1_CreditGrant()
        grant.channel = .files
        grant.amount = 1
        var envelope = Tandem_V1_Envelope()
        envelope.channel = .control
        envelope.seq = 1
        envelope.payload = .creditGrant(grant)
        try await pair.endB.send(try FrameEncoder.encode(envelope))

        try await pendingSend.value
        #expect(completed.withLock { $0 } == true)
    }

    @Test
    func frameWriter_tenFilesQueuedThenNotify_notifyWrittenWithinTwoFrames() async throws {
        let pair = InMemoryConnectionPair()
        let sink = StepSink(forward: pair.endA.send)
        let sender = ChannelMultiplexer(source: InMemoryFrameSource(pair.endA), sink: sink.write)

        var fileSends: [Task<Void, Error>] = []
        for _ in 0..<10 {
            fileSends.append(Task { try await sender.send(.files, payload: .heartbeat(Tandem_V1_Heartbeat())) })
        }

        // Synchronizes on the writer having picked its very first frame (necessarily a FILES
        // frame, the only channel with anything queued yet) and being gated on it -- so none of
        // the 10 FILES sends have reached the wire yet.
        await sink.waitUntilWriteStarted()
        for _ in 0..<30 { await Task.yield() } // let the other 9 FILES sends finish enqueuing

        let notifySend = Task { try await sender.send(.notify, payload: .heartbeat(Tandem_V1_Heartbeat())) }
        for _ in 0..<10 { await Task.yield() } // let the NOTIFY send finish enqueuing

        for _ in 0..<15 { await sink.releaseOne() }

        for task in fileSends { try await task.value }
        try await notifySend.value

        let wire = InMemoryFrameSource(pair.endB)
        var channels: [Tandem_V1_Channel] = []
        for _ in 0..<11 {
            guard case .frame(let envelope)? = try await FrameDecoder.decode(from: wire) else {
                Issue.record("expected a decodable frame")
                return
            }
            channels.append(envelope.channel)
        }

        let notifyIndex = channels.firstIndex(of: .notify)
        #expect(notifyIndex != nil)
        let message = "NOTIFY must not wait behind more than one other FILES frame once queued: \(channels)"
        #expect((notifyIndex ?? channels.count) <= 2, "\(message)")
    }

    @Test
    func flowControl_stalledNotifyConsumer_filesFramesStillDelivered() async throws {
        let pair = InMemoryConnectionPair()
        let receiver = ChannelMultiplexer(source: InMemoryFrameSource(pair.endB), sink: pair.endB.send)
        await receiver.start()

        // Requested (E11-06 guarantee: this channel's own stream exists from `init`), but never
        // read from -- this is the "stalled consumer."
        _ = await receiver.inbound(.notify)

        let filesStream = await receiver.inbound(.files)
        var filesIterator = filesStream.makeAsyncIterator()

        func sendFromPeer(_ channel: Tandem_V1_Channel, seq: UInt64) async throws {
            var envelope = Tandem_V1_Envelope()
            envelope.channel = channel
            envelope.seq = seq
            envelope.payload = .heartbeat(Tandem_V1_Heartbeat())
            try await pair.endA.send(try FrameEncoder.encode(envelope))
        }

        for seq in UInt64(1)...5 {
            try await sendFromPeer(.notify, seq: seq)
        }

        for seq in UInt64(1)...3 {
            try await sendFromPeer(.files, seq: seq)
            let frame = await filesIterator.next()
            #expect(frame?.channel == .files)
            #expect(frame?.seq == seq)
        }

        let closeReason = await receiver.closeReason
        #expect(closeReason == nil)
    }

    @Test
    func flowControl_consumedPastTrigger_sendsExactlyOneCreditGrant() async throws {
        let pair = InMemoryConnectionPair()
        let receiver = ChannelMultiplexer(source: InMemoryFrameSource(pair.endB), sink: pair.endB.send)
        await receiver.start()

        let notifyStream = await receiver.inbound(.notify)
        var notifyIterator = notifyStream.makeAsyncIterator()

        let cap = CreditCaps.capFor(.notify)
        let trigger = cap / 2
        for seq in UInt64(1)...UInt64(trigger) {
            var envelope = Tandem_V1_Envelope()
            envelope.channel = .notify
            envelope.seq = seq
            envelope.payload = .heartbeat(Tandem_V1_Heartbeat())
            try await pair.endA.send(try FrameEncoder.encode(envelope))
            _ = await notifyIterator.next() // application-level consumption; the last one crosses the trigger
        }

        let peerWire = InMemoryFrameSource(pair.endA)
        guard case .frame(let grantEnvelope)? = try await FrameDecoder.decode(from: peerWire) else {
            Issue.record("expected a CreditGrant frame")
            return
        }
        #expect(grantEnvelope.channel == .control)
        guard case .creditGrant(let grant)? = grantEnvelope.payload else {
            Issue.record("expected a creditGrant payload, got \(String(describing: grantEnvelope.payload))")
            return
        }
        #expect(grant.channel == .notify)
        #expect(grant.amount == trigger)

        // Exactly one grant: everything ever written in this direction is that one frame.
        let capturedBytes = await pair.captured(.bToA)
        let expectedBytes = try FrameEncoder.encode(grantEnvelope)
        #expect(capturedBytes == expectedBytes)
    }

    @Test
    func flowControl_peerSendsBeyondGrant_closesWithCreditViolation() async throws {
        let pair = InMemoryConnectionPair()
        let receiver = ChannelMultiplexer(source: InMemoryFrameSource(pair.endB), sink: pair.endB.send)
        await receiver.start()

        let cap = CreditCaps.capFor(.files)
        for seq in UInt64(1)...UInt64(cap + 1) {
            var envelope = Tandem_V1_Envelope()
            envelope.channel = .files
            envelope.seq = seq
            envelope.payload = .heartbeat(Tandem_V1_Heartbeat())
            try await pair.endA.send(try FrameEncoder.encode(envelope))
        }

        let closeReason = await waitForClose(of: receiver)
        #expect(closeReason == .creditViolation(.files))
    }

    @Test
    func flowControl_peerGrantAboveCap_closesWithCreditViolation() async throws {
        let pair = InMemoryConnectionPair()
        let receiver = ChannelMultiplexer(source: InMemoryFrameSource(pair.endB), sink: pair.endB.send)
        await receiver.start()

        var grant = Tandem_V1_CreditGrant()
        grant.channel = .files
        // `sendLedger[.files]` already starts full at its cap (the initial grant, SPEC.md): any
        // positive amount here is already above the cap.
        grant.amount = 1

        var envelope = Tandem_V1_Envelope()
        envelope.channel = .control
        envelope.seq = 1
        envelope.payload = .creditGrant(grant)
        try await pair.endA.send(try FrameEncoder.encode(envelope))

        let closeReason = await waitForClose(of: receiver)
        #expect(closeReason == .creditViolation(.files))
    }

    @Test
    func flowControl_controlChannel_neverSuspendsOnCredit() async throws {
        let pair = InMemoryConnectionPair()
        let sender = ChannelMultiplexer(source: InMemoryFrameSource(pair.endA), sink: pair.endA.send)

        let sendCount = 200 // well past CreditCaps.protocolMax: a feature channel would suspend here.
        for _ in 0..<sendCount {
            try await sender.send(.control, payload: .heartbeat(Tandem_V1_Heartbeat()))
        }

        let wire = InMemoryFrameSource(pair.endB)
        for expectedSeq in UInt64(1)...UInt64(sendCount) {
            guard case .frame(let envelope)? = try await FrameDecoder.decode(from: wire) else {
                Issue.record("expected a decodable frame")
                return
            }
            #expect(envelope.channel == .control)
            #expect(envelope.seq == expectedSeq)
        }
    }

    /// Polls `multiplexer.closeReason` until it becomes non-`nil` or this gives up. Used instead
    /// of a synchronizing stream read where reading itself would be the very application-level
    /// consumption event under test (crediting the peer back and masking the violation).
    private func waitForClose(of multiplexer: ChannelMultiplexer) async -> MultiplexerClose? {
        for _ in 0..<1000 {
            if let closeReason = await multiplexer.closeReason {
                return closeReason
            }
            await Task.yield()
        }
        return nil
    }
}

/// A hand-rolled ``ChannelMultiplexer/OutboundSink`` that suspends every call until
/// ``releaseOne()`` has been called once for it (in call order), used to hold the round-robin
/// writer at a controlled point so a test can enqueue several sends before any of them reach the
/// wire. ``releaseOne()`` called with nothing currently waiting banks a credit for the next call
/// instead of being lost.
actor StepSink {
    private let forward: @Sendable (Data) async throws -> Void
    private var pendingRelease: CheckedContinuation<Void, Never>?
    private var releaseCredits = 0
    private var started: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    init(forward: @escaping @Sendable (Data) async throws -> Void) {
        self.forward = forward
    }

    func write(_ data: Data) async throws {
        if !hasStarted {
            hasStarted = true
            started?.resume()
            started = nil
        }
        if releaseCredits > 0 {
            releaseCredits -= 1
        } else {
            await withCheckedContinuation { pendingRelease = $0 }
        }
        try await forward(data)
    }

    /// Suspends until the first `write(_:)` call has started (and is now waiting on a release).
    func waitUntilWriteStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { started = $0 }
    }

    func releaseOne() {
        if let pendingRelease {
            self.pendingRelease = nil
            pendingRelease.resume()
        } else {
            releaseCredits += 1
        }
    }
}
