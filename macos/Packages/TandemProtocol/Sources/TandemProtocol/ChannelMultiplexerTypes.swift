import Foundation

/// One decoded frame routed to its channel's inbound stream (``ChannelMultiplexer/inbound(_:)``).
/// `channel` is redundant with which stream it arrived on, but is kept so a consumer (or a test)
/// can assert routing without depending on which stream instance it read from.
public struct InboundFrame: Sendable, Equatable {
    public let channel: Tandem_V1_Channel
    public let seq: UInt64
    public let ack: UInt64
    public let payload: Tandem_V1_Envelope.OneOf_Payload?
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
    /// The local side asked this multiplexer to stop (``ChannelMultiplexer/stop()``) --
    /// `TandemSession/close()` (E12-12), never a wire-observed condition.
    case localClose
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
extension ChannelMultiplexer {
    /// Stops this multiplexer from the local side (``TandemSession/close()``, E12-12): equivalent
    /// to how a fatal peer/framing condition stops it (``finish(_:)``), but chosen locally rather
    /// than detected off the wire. Finishes every ``inbound(_:)`` stream and fails every send
    /// still queued. Safe to call more than once, or once the multiplexer has already stopped for
    /// another reason.
    func stop() async {
        await finish(.localClose)
    }
}

public struct InboundFrameStream: AsyncSequence, Sendable {
    public typealias Element = InboundFrame

    fileprivate let base: AsyncStream<InboundFrame>
    fileprivate let onConsumed: @Sendable () async -> Void

    init(base: AsyncStream<InboundFrame>, onConsumed: @escaping @Sendable () async -> Void) {
        self.base = base
        self.onConsumed = onConsumed
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        fileprivate var base: AsyncStream<InboundFrame>.AsyncIterator
        fileprivate let onConsumed: @Sendable () async -> Void

        public mutating func next() async -> InboundFrame? {
            guard let frame = await base.next() else { return nil }
            await onConsumed()
            return frame
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeAsyncIterator(), onConsumed: onConsumed)
    }
}
