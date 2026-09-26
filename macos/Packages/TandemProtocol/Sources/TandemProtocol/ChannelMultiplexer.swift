import Foundation

/// One decoded frame routed to its channel's inbound stream (``ChannelMultiplexer/inbound(_:)``).
/// `channel` is redundant with which stream it arrived on, but is kept so a consumer (or a test)
/// can assert routing without depending on which stream instance it read from.
struct InboundFrame: Sendable, Equatable {
    let channel: Tandem_V1_Channel
    let seq: UInt64
    let ack: UInt64
    let payload: Tandem_V1_Envelope.OneOf_Payload?
}

/// Why a ``ChannelMultiplexer`` stopped routing frames. Every case is a fail-closed stop: the
/// reader task exits and every channel's inbound stream finishes (docs/protocol/SPEC.md
/// invariant 5).
enum MultiplexerClose: Sendable, Equatable {
    /// The peer closed its sending direction in an orderly way at a frame boundary
    /// (``FrameDecoder/decode(from:)`` returned `nil`) -- not itself a protocol violation.
    case peerClosed
    /// The underlying ``FrameSource`` threw (a transport-level failure, e.g. a TCP reset).
    case sourceFailed
    /// A framing-level rejection (``FrameDecoder``) or a seq/ack rule violation
    /// (docs/planning/decisions.md D-57). Always `CloseCode.malformedFrame` today: D-57 assigns
    /// `SEQ_REGRESSION` to the existing `MALFORMED_FRAME` close code rather than a new one.
    case violation(CloseCode, MalformedFrameReason)
}

/// Thrown by ``ChannelMultiplexer/send(_:payload:)`` once the multiplexer has stopped
/// (``MultiplexerClose``): fail closed rather than writing more bytes to a socket whose framing
/// contract with the peer is no longer trusted (docs/protocol/SPEC.md invariant 5).
enum MultiplexerError: Error, Sendable, Equatable {
    case closed(MultiplexerClose)
}

/// Routes inbound `Envelope` frames to a per-channel `AsyncStream` and assigns outbound `seq`/
/// `ack` (docs/protocol/SPEC.md #framing-and-envelope, #channels-and-flow-control-credits;
/// `docs/planning/decisions.md` D-57). Swift counterpart to the Android `ChannelMultiplexer`
/// (E11-05).
///
/// One reader task decodes frames from the injected ``FrameSource`` and dispatches each to the
/// `AsyncStream` for its `Envelope.channel`, so a frame sent on one channel is never observed on
/// another channel's stream. ``send(_:payload:)`` may be called concurrently from any number of
/// tasks; a single internal FIFO write lock (not the actor's own reentrant exclusivity, which is
/// not enough across an `await`) serializes every outgoing frame -- assigning a channel's next
/// `seq` and writing the encoded frame is one atomic step -- so bytes for a given channel always
/// reach the wire in the order their `seq` values were assigned, matching the Android twin's
/// `Mutex`-guarded guarantee (`android/.../ChannelMultiplexer.kt`). ``finish(_:)`` takes the same
/// lock, so it waits for any in-flight write before completing, and no write started after it can
/// still land on the wire. Each channel's own `seq` counter increments independently and by
/// exactly 1 (docs/protocol/SPEC.md "Counters on different channels ... are entirely
/// independent").
///
/// `TandemProtocol` may not depend on `TandemTransport` (PRD module rules: transport depends on
/// protocol, never the reverse; see this package's `Package.swift`), and the wire types this type
/// operates on (`Tandem_V1_Envelope`, `Tandem_V1_Channel`, ...) are internal to this module (the
/// generated code is not built with `Visibility=Public`). So, unlike the backlog's "in
/// TandemTransport" phrasing, this lives in `TandemProtocol` and talks to the outside world only
/// through the existing ``FrameSource`` seam (E11-04) for inbound bytes and an injected outbound
/// sink closure for outbound bytes -- never through `ByteStreamConnection` directly. A
/// `ByteStreamConnection`'s own `send(_:)` already matches this sink's signature, so no adapter is
/// needed on that side (unlike `FrameSource`, which needs `InMemoryFrameSource` to adapt
/// `receive()`'s chunking to `read(exactly:)`).
actor ChannelMultiplexer {
    /// Sends one already-framed (length-prefixed) frame's bytes to the peer, suspending under
    /// backpressure exactly like `ByteStreamConnection.send(_:)` -- which satisfies this
    /// signature directly.
    typealias OutboundSink = @Sendable (Data) async throws -> Void

    /// The channel set this type routes: every `Tandem_V1_Channel` except `.unspecified`
    /// (`FrameDecoder` already rejects `.unspecified`/`.UNRECOGNIZED` as `UNKNOWN_CHANNEL` before
    /// a decoded frame ever reaches this type, so every frame this type sees carries one of
    /// these).
    private static let routedChannels: [Tandem_V1_Channel] =
        Tandem_V1_Channel.allCases.filter { $0 != .unspecified }

    private let source: FrameSource
    private let sink: OutboundSink

    private var streams: [Tandem_V1_Channel: AsyncStream<InboundFrame>] = [:]
    private var continuations: [Tandem_V1_Channel: AsyncStream<InboundFrame>.Continuation] = [:]

    /// This side's own per-channel outbound `seq` counter: the last `seq` this side has sent on
    /// that channel (0 before this side has sent anything on it).
    private var outgoingSeq: [Tandem_V1_Channel: UInt64] = [:]
    /// The ack watermark this side reports for each channel: the highest `seq` received from the
    /// peer on that channel, in contiguous order (0 before anything has arrived on it).
    private var inboundWatermark: [Tandem_V1_Channel: UInt64] = [:]
    /// `seq` values received above a channel's current watermark but not yet folded into it
    /// (held back by an earlier gap), per channel.
    private var inboundPendingAboveWatermark: [Tandem_V1_Channel: Set<UInt64>] = [:]

    private var readerTask: Task<Void, Never>?
    private(set) var closeReason: MultiplexerClose?

    /// Whether the FIFO write lock (below) is currently held. `send(_:payload:)` and `finish(_:)`
    /// are this actor's only two critical sections that must never overlap in time (assigning a
    /// `seq` + writing it, and completing the close, respectively); everything else may still run
    /// interleaved between an acquire and its release, same as any other actor reentrancy.
    private var writeLockHeld = false
    /// Callers waiting to acquire the write lock, in arrival order (FIFO): `acquireWriteLock()`
    /// suspends by appending a continuation here, and `releaseWriteLock()` resumes the oldest one
    /// first, so callers reach their critical section in the order they asked for it.
    private var writeLockWaiters: [CheckedContinuation<Void, Never>] = []

    init(source: FrameSource, sink: @escaping OutboundSink) {
        self.source = source
        self.sink = sink
        for channel in Self.routedChannels {
            let (stream, continuation) = AsyncStream<InboundFrame>.makeStream(bufferingPolicy: .unbounded)
            streams[channel] = stream
            continuations[channel] = continuation
        }
    }

    /// Starts the single reader task that decodes frames from `source` and routes them. Calling
    /// this more than once, or after the multiplexer has already stopped, is a no-op.
    func start() {
        guard readerTask == nil, closeReason == nil else { return }
        readerTask = Task { [weak self] in
            await self?.readLoop()
        }
    }

    /// The `AsyncStream` a frame on `channel` is yielded on. Returns the same stream on every
    /// call for a given `channel` (there is one stream per channel for this multiplexer's
    /// lifetime, created at `init`), so a frame arriving before any caller has requested this
    /// stream is never dropped.
    func inbound(_ channel: Tandem_V1_Channel) -> AsyncStream<InboundFrame> {
        guard let stream = streams[channel] else {
            preconditionFailure("\(channel) is not a routable channel")
        }
        return stream
    }

    /// Encodes and sends `payload` on `channel`: assigns the next `seq` for `channel` (this
    /// side's own counter, starting at 1 and incrementing by exactly 1 per send on that channel)
    /// and the current ack watermark this side holds for `channel`
    /// (docs/protocol/SPEC.md #framing-and-envelope "Envelope fields").
    ///
    /// - Throws: ``MultiplexerError/closed(_:)`` if this multiplexer has already stopped (fail
    ///   closed: no more bytes are written once the connection's framing contract with the peer
    ///   is no longer trusted); whatever `FrameEncoder.encode(_:)` or the outbound sink throws
    ///   otherwise.
    func send(_ channel: Tandem_V1_Channel, payload: Tandem_V1_Envelope.OneOf_Payload) async throws {
        precondition(Self.routedChannels.contains(channel), "\(channel) is not a routable channel")
        await acquireWriteLock()
        defer { releaseWriteLock() }

        // Checked only after acquiring the lock: a `finish(_:)` that completed while this call
        // was waiting its turn must be observed here, and no write may start once it has run.
        if let closeReason {
            throw MultiplexerError.closed(closeReason)
        }

        let seq = (outgoingSeq[channel] ?? 0) + 1
        outgoingSeq[channel] = seq

        var envelope = Tandem_V1_Envelope()
        envelope.channel = channel
        envelope.seq = seq
        envelope.ack = inboundWatermark[channel] ?? 0
        envelope.payload = payload

        let frame = try FrameEncoder.encode(envelope)
        try await sink(frame)
    }

    /// Acquires the FIFO write lock, suspending until every earlier caller (of either `send` or
    /// `finish`) has released it. Not actor reentrancy: the lock's own state (`writeLockHeld`/
    /// `writeLockWaiters`) is only ever touched while holding the actor's exclusivity, but the
    /// *suspension* while waiting is what makes the guarded section behave as a true non-reentrant
    /// critical section across the `await sink(frame)` inside it.
    private func acquireWriteLock() async {
        if !writeLockHeld {
            writeLockHeld = true
            return
        }
        await withCheckedContinuation { continuation in
            writeLockWaiters.append(continuation)
        }
    }

    /// Releases the FIFO write lock: resumes the oldest waiter (which then holds the lock) or,
    /// if none are waiting, marks the lock free.
    private func releaseWriteLock() {
        guard !writeLockWaiters.isEmpty else {
            writeLockHeld = false
            return
        }
        writeLockWaiters.removeFirst().resume()
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

    /// Applies the seq/ack watermark rules (`docs/planning/decisions.md` D-57) to a decoded
    /// frame and, if it passes, yields it on its channel's stream. Returns `false` (having
    /// already called `finish(_:)`) on a violation.
    private func accept(_ envelope: Tandem_V1_Envelope) async -> Bool {
        let channel = envelope.channel
        if let reason = validateAndRecord(seq: envelope.seq, ack: envelope.ack, channel: channel) {
            await finish(.violation(.malformedFrame, reason))
            return false
        }

        let frame = InboundFrame(channel: channel, seq: envelope.seq, ack: envelope.ack, payload: envelope.payload)
        continuations[channel]?.yield(frame)
        return true
    }

    /// - Returns: the violation reason if `seq` or `ack` violates D-57 (a `seq` of 0, at or below
    ///   the current watermark, or a duplicate of an already-received above-watermark value; an
    ///   `ack` above the highest `seq` this side has itself sent on `channel`; or `channel`'s
    ///   above-watermark pending set already holding ``CreditCaps/protocolMax`` entries -- D-64: a
    ///   legitimate, credit-bound peer can never make this many `seq` values pending at once). On
    ///   success (`nil`), records `seq` and advances the watermark past any newly-contiguous run
    ///   (docs/protocol/SPEC.md "Sequence and acknowledgement violations").
    private func validateAndRecord(seq: UInt64, ack: UInt64, channel: Tandem_V1_Channel) -> MalformedFrameReason? {
        guard ack <= (outgoingSeq[channel] ?? 0) else { return .seqRegression }

        var watermark = inboundWatermark[channel] ?? 0
        var pending = inboundPendingAboveWatermark[channel] ?? []
        guard seq > watermark, !pending.contains(seq) else { return .seqRegression }
        guard pending.count < Int(CreditCaps.protocolMax) else { return .seqGapTooLarge }

        pending.insert(seq)
        while pending.contains(watermark + 1) {
            watermark += 1
            pending.remove(watermark)
        }

        inboundWatermark[channel] = watermark
        inboundPendingAboveWatermark[channel] = pending
        return nil
    }

    /// Completes this multiplexer's close exactly once. Takes the write lock first, so it waits
    /// for any write already in flight (assigned a `seq` and now suspended in `sink`) to finish,
    /// and so no `send(_:payload:)` waiting behind it can start a write afterwards -- it will
    /// acquire the lock only once this has already set `closeReason`, and then throw.
    private func finish(_ reason: MultiplexerClose) async {
        await acquireWriteLock()
        defer { releaseWriteLock() }
        guard closeReason == nil else { return }
        closeReason = reason
        for continuation in continuations.values {
            continuation.finish()
        }
    }
}
