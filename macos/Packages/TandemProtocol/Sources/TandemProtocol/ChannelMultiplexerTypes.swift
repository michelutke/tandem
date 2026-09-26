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
    /// A credit-flow-control violation on `channel` (docs/protocol/SPEC.md
    /// #channels-and-flow-control-credits; `docs/planning/decisions.md` D-64; E11-08): the peer
    /// transmitted a frame on `channel` past the credit this side had granted it, or a
    /// `CreditGrant` it sent named an amount that would take this side's own send balance for
    /// `channel` above that channel's cap. Always `CloseCode.creditViolation`.
    case creditViolation(Tandem_V1_Channel)
}

/// Thrown by ``ChannelMultiplexer/send(_:payload:)`` once the multiplexer has stopped
/// (``MultiplexerClose``): fail closed rather than writing more bytes to a socket whose framing
/// contract with the peer is no longer trusted (docs/protocol/SPEC.md invariant 5).
enum MultiplexerError: Error, Sendable, Equatable {
    case closed(MultiplexerClose)
}

/// Wraps a channel's inbound frame stream so that a caller actually pulling a frame off it (not
/// merely the frame having been decoded and routed) is what counts as this channel's
/// application-level consumption for credit-flow-control replenishment (docs/protocol/SPEC.md
/// #channels-and-flow-control-credits "Consume"; E11-08). Behaves exactly like the
/// `AsyncStream<InboundFrame>` it wraps from a caller's point of view.
struct InboundFrameStream: AsyncSequence, Sendable {
    typealias Element = InboundFrame

    fileprivate let base: AsyncStream<InboundFrame>
    fileprivate let onConsumed: @Sendable () async -> Void

    init(base: AsyncStream<InboundFrame>, onConsumed: @escaping @Sendable () async -> Void) {
        self.base = base
        self.onConsumed = onConsumed
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        fileprivate var base: AsyncStream<InboundFrame>.AsyncIterator
        fileprivate let onConsumed: @Sendable () async -> Void

        mutating func next() async -> InboundFrame? {
            guard let frame = await base.next() else { return nil }
            await onConsumed()
            return frame
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeAsyncIterator(), onConsumed: onConsumed)
    }
}
