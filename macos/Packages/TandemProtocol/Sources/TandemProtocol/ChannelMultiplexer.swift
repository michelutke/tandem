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
/// another channel's stream. Outbound sends are serialized through this actor, so each channel's
/// own `seq` counter increments independently and by exactly 1
/// (docs/protocol/SPEC.md "Counters on different channels ... are entirely independent").
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

    private func readLoop() async {
        do {
            while true {
                guard let result = try await FrameDecoder.decode(from: source) else {
                    finish(.peerClosed)
                    return
                }
                switch result {
                case .frame(let envelope):
                    guard accept(envelope) else { return }
                case .rejected(let closeCode, let reason):
                    finish(.violation(closeCode, reason))
                    return
                }
            }
        } catch {
            finish(.sourceFailed)
        }
    }

    /// Applies the seq/ack watermark rules (`docs/planning/decisions.md` D-57) to a decoded
    /// frame and, if it passes, yields it on its channel's stream. Returns `false` (having
    /// already called `finish(_:)`) on a violation.
    private func accept(_ envelope: Tandem_V1_Envelope) -> Bool {
        let channel = envelope.channel
        guard validateAndRecord(seq: envelope.seq, ack: envelope.ack, channel: channel) else {
            finish(.violation(.malformedFrame, .seqRegression))
            return false
        }

        let frame = InboundFrame(channel: channel, seq: envelope.seq, ack: envelope.ack, payload: envelope.payload)
        continuations[channel]?.yield(frame)
        return true
    }

    /// - Returns: `false` if `seq` or `ack` violates D-57 (a `seq` of 0, at or below the current
    ///   watermark, or a duplicate of an already-received above-watermark value; or an `ack`
    ///   above the highest `seq` this side has itself sent on `channel`). On success, records
    ///   `seq` and advances the watermark past any newly-contiguous run
    ///   (docs/protocol/SPEC.md "Sequence and acknowledgement violations").
    private func validateAndRecord(seq: UInt64, ack: UInt64, channel: Tandem_V1_Channel) -> Bool {
        guard ack <= (outgoingSeq[channel] ?? 0) else { return false }

        var watermark = inboundWatermark[channel] ?? 0
        var pending = inboundPendingAboveWatermark[channel] ?? []
        guard seq > watermark, !pending.contains(seq) else { return false }

        pending.insert(seq)
        while pending.contains(watermark + 1) {
            watermark += 1
            pending.remove(watermark)
        }

        inboundWatermark[channel] = watermark
        inboundPendingAboveWatermark[channel] = pending
        return true
    }

    private func finish(_ reason: MultiplexerClose) {
        guard closeReason == nil else { return }
        closeReason = reason
        for continuation in continuations.values {
            continuation.finish()
        }
    }
}
