import Foundation

/// Routes inbound `Envelope` frames to a per-channel stream and assigns outbound `seq`/`ack`
/// (docs/protocol/SPEC.md #framing-and-envelope, #channels-and-flow-control-credits;
/// `docs/planning/decisions.md` D-57, D-64). Swift counterpart to the Android `ChannelMultiplexer`
/// (E11-05/E11-07).
///
/// One reader task decodes frames from the injected ``FrameSource`` and dispatches each to the
/// stream for its `Envelope.channel`, so a frame sent on one channel is never observed on another
/// channel's stream. Each channel's own `seq` counter increments independently and by exactly 1.
///
/// Outbound writes (E11-08): ``send(_:payload:)`` never writes directly. It enqueues the payload
/// on `channel`'s own FIFO queue and suspends until a single writer -- driven reactively from this
/// same actor, never a free-running loop -- has actually put it on the wire. That writer scans
/// every routable channel in round-robin order each time it picks a frame, so a channel with many
/// queued frames (e.g. a large `FILES` transfer) cannot make a newly queued frame on another
/// channel (e.g. `NOTIFY`) wait behind more than one frame per other channel with something ready
/// to send. `CONTROL` is always ready (it carries no credit ledger, SPEC.md "CONTROL is exempt");
/// a feature channel is only ready while its own send-side ``CreditLedger`` (E11-14) balance is
/// above zero, so a feature-channel send suspends under credit exhaustion and resumes once a peer
/// `CreditGrant` is applied (``applyIncomingCreditGrant(_:)``). Within one channel, frames still
/// leave in the order `send` was called (FIFO).
///
/// Inbound credit accounting mirrors the same per-channel caps: arrival of a feature-channel frame
/// spends one credit from this side's belief of the peer's remaining balance; a peer that spends
/// past that belief is closed with ``MultiplexerClose/creditViolation(_:)``. Actually taking a
/// frame off ``inbound(_:)``'s stream -- not merely decoding it -- is this side's own
/// application-level consumption; once enough of it accumulates to cross half the channel's cap,
/// this side sends the peer exactly one `CreditGrant` restoring its belief of the peer's balance to
/// exactly the cap (never above, D-64), so a stalled consumer on one channel stops that channel's
/// own replenishment without affecting any other (``InboundFrameStream``, ``frameConsumed(_:)``).
/// An inbound `CreditGrant` above this side's own cap for that channel is also a
/// ``MultiplexerClose/creditViolation(_:)`` (D-64: reported, never clamped).
///
/// ``sent``/``received`` (E20-05/E20-15): a connection's liveness contract (SPEC.md #heartbeat,
/// E01-07) and D-61's `CONTROL` receive cap are both defined at "any frame", independent of which
/// channel it is on or whether any consumer ever pulls it off ``inbound(_:)`` -- so both are
/// reported as their own broadcast streams here, never by consuming a channel's own stream (which
/// would otherwise steal frames from whatever else is reading it).
///
/// `TandemProtocol` may not depend on `TandemTransport` (PRD module rules: transport depends on
/// protocol, never the reverse), and the wire types this type operates on are internal to this
/// module, so this lives in `TandemProtocol` and talks to the outside world only through the
/// existing ``FrameSource`` seam (E11-04) for inbound bytes and an injected outbound sink closure
/// for outbound bytes -- never through `ByteStreamConnection` directly, though its own `send(_:)`
/// already matches this sink's signature, so no adapter is needed on that side.
public actor ChannelMultiplexer {
    /// Sends one already-framed (length-prefixed) frame's bytes to the peer, suspending under
    /// backpressure exactly like `ByteStreamConnection.send(_:)` -- which satisfies this
    /// signature directly.
    public typealias OutboundSink = @Sendable (Data) async throws -> Void

    /// The channel set this type routes: every `Tandem_V1_Channel` except `.unspecified`
    /// (`FrameDecoder` already rejects `.unspecified`/`.UNRECOGNIZED` as `UNKNOWN_CHANNEL` before
    /// a decoded frame ever reaches this type, so every frame this type sees carries one of
    /// these).
    private static let routedChannels: [Tandem_V1_Channel] =
        Tandem_V1_Channel.allCases.filter { $0 != .unspecified }

    /// `routedChannels` minus `.control`: the eight channels a `CreditLedger` applies to
    /// (docs/protocol/SPEC.md "CONTROL is exempt from credit accounting"). Internal, not
    /// `private`: `ChannelMultiplexer+CreditFlow.swift`'s `applyIncomingCreditGrant(_:)` (same
    /// module, different file) also reads this.
    static let featureChannels: [Tandem_V1_Channel] =
        routedChannels.filter { $0 != .control }

    private let source: FrameSource
    private let sink: OutboundSink

    private var streams: [Tandem_V1_Channel: AsyncStream<InboundFrame>] = [:]
    private var continuations: [Tandem_V1_Channel: AsyncStream<InboundFrame>.Continuation] = [:]

    /// This side's own per-channel outbound `seq` counter: the last `seq` this side has sent on
    /// that channel (0 before this side has sent anything on it). Internal, not `private`: also
    /// read/written by `ChannelMultiplexer+CreditFlow.swift`'s `validateAndRecord(seq:ack:channel:)`.
    var outgoingSeq: [Tandem_V1_Channel: UInt64] = [:]
    /// The ack watermark this side reports for each channel: the highest `seq` received from the
    /// peer on that channel, in contiguous order (0 before anything has arrived on it). Internal
    /// for the same reason as ``outgoingSeq``.
    var inboundWatermark: [Tandem_V1_Channel: UInt64] = [:]
    /// `seq` values received above a channel's current watermark but not yet folded into it
    /// (held back by an earlier gap), per channel. Internal for the same reason as ``outgoingSeq``.
    var inboundPendingAboveWatermark: [Tandem_V1_Channel: Set<UInt64>] = [:]

    /// This side's own send-side credit balance for each feature channel (E11-14): consumed by 1
    /// each time this side actually writes a frame on that channel, replenished by an inbound
    /// `CreditGrant` (``applyIncomingCreditGrant(_:)``, `ChannelMultiplexer+CreditFlow.swift`).
    /// Absent for `.control` (exempt). Internal for the same reason as ``outgoingSeq``.
    var sendLedger: [Tandem_V1_Channel: CreditLedger] = [:]
    /// This side's belief of the peer's remaining send-side balance for each feature channel:
    /// consumed by 1 as each of the peer's frames arrives (a peer spending past this is
    /// ``MultiplexerClose/creditViolation(_:)``), replenished when this side sends the peer a
    /// `CreditGrant` (``frameConsumed(_:)``, `ChannelMultiplexer+CreditFlow.swift`). Absent for
    /// `.control` (exempt). Internal for the same reason as ``outgoingSeq``.
    var receiveLedger: [Tandem_V1_Channel: CreditLedger] = [:]
    /// Frames actually pulled off each feature channel's inbound stream (``InboundFrameStream``)
    /// since the last `CreditGrant` this side sent for it (or since the start, if none yet).
    /// Reaching half the channel's cap is the SPEC-defined replenishment trigger
    /// (``frameConsumed(_:)``, `ChannelMultiplexer+CreditFlow.swift`). Internal for the same
    /// reason as ``outgoingSeq``.
    var consumedSinceLastGrant: [Tandem_V1_Channel: UInt32] = [:]

    private var readerTask: Task<Void, Never>?
    public private(set) var closeReason: MultiplexerClose?
    // Internal, not `private`: `awaitClose()` (`ChannelMultiplexerTypes.swift`) appends to this.
    var closeWaiters: [CheckedContinuation<MultiplexerClose, Never>] = []

    /// Fires once for every frame this multiplexer actually writes to the wire, on any channel
    /// (SPEC.md #heartbeat, E01-07/E20-05: "any frame it sends" resets the Mac's own idle-send
    /// timer). Never finishes until ``finish(_:)`` runs.
    public nonisolated let sent: AsyncStream<Void>
    private let sentContinuation: AsyncStream<Void>.Continuation

    /// Fires once for every frame this multiplexer accepts off the wire, on any channel, at the
    /// moment it is validated -- before it is ever routed to that channel's own ``inbound(_:)``
    /// stream, and regardless of whether any caller ever pulls it off there (SPEC.md #heartbeat,
    /// E01-07/E20-05: "any frame" received resets the dead-peer timer; `docs/planning/decisions.md`
    /// D-61's `CONTROL` receive cap is defined at this same granularity). Never consumes
    /// ``inbound(_:)`` itself, so observing this never drops a frame another consumer would
    /// otherwise see.
    public nonisolated let received: AsyncStream<FrameArrival>
    private let receivedContinuation: AsyncStream<FrameArrival>.Continuation

    /// One send awaiting the writer: enqueued by ``send(_:payload:)``, dequeued and turned into a
    /// wire write by ``drainLoop()``.
    private struct PendingSend {
        let payload: Tandem_V1_Envelope.OneOf_Payload
        let continuation: CheckedContinuation<Void, Error>
    }

    /// Every channel's own FIFO of sends not yet written to the wire.
    private var pendingByChannel: [Tandem_V1_Channel: [PendingSend]] = [:]
    /// Index into `routedChannels` the round-robin writer resumes scanning from next -- always the
    /// slot just past the channel it last served, so that channel goes to the back of the line
    /// (fairness across repeated calls, not just within one scan).
    private var roundRobinCursor = 0
    /// Whether a ``drainLoop()`` is currently running. At most one runs at a time; `send(_:payload:)`
    /// and `finish(_:)` only ever need to make sure one gets started (``kickDrainIfNeeded()``), never
    /// to run the loop themselves.
    private var isDraining = false

    public init(source: FrameSource, sink: @escaping OutboundSink) {
        self.source = source
        self.sink = sink
        (sent, sentContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .unbounded)
        (received, receivedContinuation) = AsyncStream<FrameArrival>.makeStream(bufferingPolicy: .unbounded)
        for channel in Self.routedChannels {
            (streams[channel], continuations[channel]) =
                AsyncStream<InboundFrame>.makeStream(bufferingPolicy: .unbounded)
        }
        for channel in Self.featureChannels {
            let cap = CreditCaps.capFor(channel)
            sendLedger[channel] = CreditLedger(cap: cap)
            receiveLedger[channel] = CreditLedger(cap: cap)
        }
    }

    /// Starts the single reader task that decodes frames from `source` and routes them. Calling
    /// this more than once, or after the multiplexer has already stopped, is a no-op.
    public func start() {
        guard readerTask == nil, closeReason == nil else { return }
        readerTask = Task { [weak self] in
            await self?.readLoop()
        }
    }

    /// The stream a frame on `channel` is yielded on. Returns an equivalent stream on every call
    /// for a given `channel` (there is one underlying `AsyncStream` per channel for this
    /// multiplexer's lifetime, created at `init`), so a frame arriving before any caller has
    /// requested this stream is never dropped. Actually pulling a frame off the returned stream is
    /// this channel's application-level consumption for credit-flow-control replenishment
    /// (``InboundFrameStream``).
    func inbound(_ channel: Tandem_V1_Channel) -> InboundFrameStream {
        guard let stream = streams[channel] else {
            preconditionFailure("\(channel) is not a routable channel")
        }
        return InboundFrameStream(base: stream) { [weak self] in
            await self?.frameConsumed(channel)
        }
    }

    /// Sends `payload` on `channel`: assigns the next `seq` for `channel` (this side's own
    /// counter, starting at 1 and incrementing by exactly 1 per send on that channel) and the
    /// current ack watermark this side holds for `channel`
    /// (docs/protocol/SPEC.md #framing-and-envelope "Envelope fields") once the fair round-robin
    /// writer actually puts it on the wire (this type's own doc comment).
    ///
    /// Suspends while `channel` is a feature channel (not `.control`) whose send-side credit
    /// balance is currently zero, resuming once that balance is replenished
    /// (``applyIncomingCreditGrant(_:)``). `.control` never suspends on credit (SPEC.md "CONTROL
    /// is exempt").
    ///
    /// - Throws: ``MultiplexerError/closed(_:)`` if this multiplexer has already stopped, or
    ///   stops while this call is still queued (fail closed: no more bytes are written once the
    ///   connection's framing contract with the peer is no longer trusted); whatever
    ///   `FrameEncoder.encode(_:)` or the outbound sink throws otherwise.
    func send(_ channel: Tandem_V1_Channel, payload: Tandem_V1_Envelope.OneOf_Payload) async throws {
        precondition(Self.routedChannels.contains(channel), "\(channel) is not a routable channel")
        if let closeReason {
            throw MultiplexerError.closed(closeReason)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingByChannel[channel, default: []].append(PendingSend(payload: payload, continuation: continuation))
            kickDrainIfNeeded()
        }
    }

    /// Starts ``drainLoop()`` if none is currently running. Safe to call any number of times --
    /// only the first call while idle actually spawns work. Internal, not `private`:
    /// `ChannelMultiplexer+CreditFlow.swift`'s `applyIncomingCreditGrant(_:)` also calls this.
    func kickDrainIfNeeded() {
        guard !isDraining else { return }
        isDraining = true
        Task { [weak self] in await self?.drainLoop() }
    }

    /// The single writer: repeatedly picks the next ready frame (``nextWritable()``), writes it,
    /// and resumes its sender, until nothing is ready. Only one instance of this loop ever runs at
    /// a time (``isDraining``), so picking a channel, assigning its `seq`, and writing it is
    /// effectively one atomic step with respect to every other channel's writes -- bytes for a
    /// given channel always reach the wire in the order their `seq` values were assigned.
    private func drainLoop() async {
        while true {
            guard let (channel, item) = nextWritable() else {
                isDraining = false
                return
            }

            if let closeReason {
                item.continuation.resume(throwing: MultiplexerError.closed(closeReason))
                continue
            }

            if channel != .control {
                _ = sendLedger[channel]?.consume(1)
            }

            let seq = (outgoingSeq[channel] ?? 0) + 1
            outgoingSeq[channel] = seq

            var envelope = Tandem_V1_Envelope()
            envelope.channel = channel
            envelope.seq = seq
            envelope.ack = inboundWatermark[channel] ?? 0
            envelope.payload = item.payload

            do {
                let frame = try FrameEncoder.encode(envelope)
                try await sink(frame)
                sentContinuation.yield(())
                item.continuation.resume()
            } catch {
                item.continuation.resume(throwing: error)
            }
        }
    }

    /// Picks the next queued send to write, in round-robin order starting at `roundRobinCursor`:
    /// the first channel (scanning forward, wrapping) with a non-empty queue that is also ready --
    /// `.control`, or a feature channel whose send-side balance is above zero -- or, once this
    /// multiplexer has closed, any non-empty queue at all (closed sends are failed, never written,
    /// so readiness no longer matters once there is a `closeReason`). Advances the cursor to just
    /// past the channel it picked, and removes that channel's oldest queued item (FIFO within a
    /// channel). Returns `nil` once no channel has anything left to offer right now.
    private func nextWritable() -> (Tandem_V1_Channel, PendingSend)? {
        let order = Self.routedChannels
        let closed = closeReason != nil
        for offset in 0..<order.count {
            let index = (roundRobinCursor + offset) % order.count
            let channel = order[index]
            guard var queue = pendingByChannel[channel], !queue.isEmpty else { continue }

            if !closed, channel != .control {
                let balance = sendLedger[channel]?.balance ?? 0
                guard balance > 0 else { continue }
            }

            let item = queue.removeFirst()
            pendingByChannel[channel] = queue
            roundRobinCursor = (index + 1) % order.count
            return (channel, item)
        }
        return nil
    }

    private func readLoop() async {
        do {
            while true {
                guard let result = try await FrameDecoder.decode(from: source) else {
                    await finish(.peerClosed)
                    return
                }
                switch result {
                case .frame(let envelope):
                    guard await accept(envelope) else { return }
                case .rejected(let closeCode, let reason):
                    await finish(.violation(closeCode, reason))
                    return
                }
            }
        } catch {
            await finish(.sourceFailed)
        }
    }

    /// Applies the seq/ack watermark rules (`docs/planning/decisions.md` D-57) and the
    /// credit-flow-control rules (D-64) to a decoded frame. On success, either intercepts a
    /// `CreditGrant` arriving on `.control` (``applyIncomingCreditGrant(_:)``, never forwarded to
    /// `.control`'s own consumer -- it is flow-control bookkeeping, not application data) or
    /// yields it on its channel's stream. Returns `false` (having already called `finish(_:)`) on
    /// any violation.
    private func accept(_ envelope: Tandem_V1_Envelope) async -> Bool {
        let channel = envelope.channel
        if let reason = validateAndRecord(seq: envelope.seq, ack: envelope.ack, channel: channel) {
            await finish(.violation(.malformedFrame, reason))
            return false
        }

        let isHeartbeat: Bool
        if case .heartbeat? = envelope.payload {
            isHeartbeat = true
        } else {
            isHeartbeat = false
        }
        receivedContinuation.yield(FrameArrival(channel: channel, isHeartbeat: isHeartbeat))

        if channel != .control {
            let result = receiveLedger[channel]?.consume(1)
            if result == .insufficient {
                await finish(.creditViolation(channel))
                return false
            }
        }

        if channel == .control, case .creditGrant(let grant)? = envelope.payload {
            return await applyIncomingCreditGrant(grant)
        }

        let frame = InboundFrame(channel: channel, seq: envelope.seq, ack: envelope.ack, payload: envelope.payload)
        continuations[channel]?.yield(frame)
        return true
    }

    /// Completes this multiplexer's close exactly once: records `reason`, finishes every inbound
    /// stream, and makes sure the writer runs at least once more so every still-queued send is
    /// failed with ``MultiplexerError/closed(_:)`` rather than left waiting forever
    /// (``nextWritable()`` stops honoring credit once `closeReason` is set). A write already in
    /// flight when this runs (assigned a `seq` and suspended inside the outbound sink) is
    /// unaffected -- it already committed to going out -- but ``drainLoop()`` will not start
    /// another one afterwards.
    func finish(_ reason: MultiplexerClose) async {
        guard closeReason == nil else { return }
        closeReason = reason
        for continuation in continuations.values { continuation.finish() }
        sentContinuation.finish()
        receivedContinuation.finish()
        for waiter in closeWaiters { waiter.resume(returning: reason) }
        closeWaiters = []
        kickDrainIfNeeded()
    }
}
