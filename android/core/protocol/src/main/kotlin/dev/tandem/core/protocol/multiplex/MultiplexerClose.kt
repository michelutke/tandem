package dev.tandem.core.protocol.multiplex

import dev.tandem.core.protocol.CloseCode
import dev.tandem.core.protocol.MalformedFrameReason
import dev.tandem.protocol.v1.Channel

/**
 * How [ChannelMultiplexer]'s single reader loop ended (E11-05; aligned with the macOS twin,
 * E11-06's `MultiplexerClose`). Completing [ChannelMultiplexer.closeReason] with one of these is
 * this issue's entire responsibility for a protocol violation: actually tearing down the
 * underlying connection (`ByteStream.closeGracefully`/`closeAbruptly`) is owned by whichever later
 * issue wires a real socket to this seam, since `core/protocol` has no dependency on
 * `core/transport`.
 */
sealed class MultiplexerClose {
    /**
     * A framing-level or seq/ack protocol violation (SPEC.md #errors-and-close-codes):
     * [FrameDecoder][dev.tandem.core.protocol.FrameDecoder]'s own rejections forward [closeCode]/[reason]
     * unchanged; a seq/ack violation this multiplexer itself detects (D-57) always reports
     * [CloseCode.MALFORMED_FRAME] with [MalformedFrameReason.SEQ_REGRESSION].
     */
    data class Violation(
        val closeCode: CloseCode,
        val reason: MalformedFrameReason,
    ) : MultiplexerClose()

    /**
     * A flow-control violation on [channel] (SPEC.md #channels-and-flow-control-credits, D-64;
     * E11-07): either the peer transmitted a frame on [channel] past the credit it was actually
     * granted, or the peer's own `CreditGrant` for [channel] would have taken this side's balance
     * above that channel's cap. Always closes with [CloseCode.CREDIT_VIOLATION]; unlike
     * [Violation], never [CloseCode.MALFORMED_FRAME], so it does not carry a [MalformedFrameReason].
     */
    data class CreditViolation(
        val channel: Channel,
    ) : MultiplexerClose()

    /**
     * The connection ended in an orderly way exactly at a frame boundary (SPEC.md
     * #framing-and-envelope) — not a violation, no close code.
     */
    data object PeerClosed : MultiplexerClose()

    /** Reading from [ChannelMultiplexer]'s `FrameSource` failed with [cause] (e.g. a transport I/O error). */
    data class SourceFailed(
        val cause: Throwable,
    ) : MultiplexerClose()
}
