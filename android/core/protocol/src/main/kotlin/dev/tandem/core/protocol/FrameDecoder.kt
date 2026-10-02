package dev.tandem.core.protocol

import com.google.protobuf.InvalidProtocolBufferException
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope

/**
 * FrameDecoder (E11-02): the receive-side counterpart to [FrameEncoder], reading the wire frame
 * docs/protocol/SPEC.md #framing-and-envelope defines as `frame = length_prefix envelope_bytes` —
 * a 4-byte big-endian length prefix followed by exactly that many envelope bytes. Reads through
 * the [FrameSource] seam rather than `core/transport`'s `ByteStream` (this module has no
 * dependency on `core/transport`; see [FrameSource]).
 *
 * [length_prefix] is checked against [FrameEncoder.MAX_ENVELOPE_BYTES] using only the 4 prefix
 * bytes, before any payload buffer is allocated (SPEC.md: "MUST compare `length_prefix` against
 * the 1 MiB maximum before allocating any buffer sized from it"). Every rejection case in
 * SPEC.md's rejection-cases table maps to [DecodeResult.Rejected] with the single
 * [CloseCode.MALFORMED_FRAME] close code and a [MalformedFrameReason] local diagnostic — never a
 * partial parse, never anything emitted for the failed frame.
 */
object FrameDecoder {
    private const val LENGTH_PREFIX_BYTES = 4
    private const val BYTE_BITS = 8
    private const val BYTE_MASK = 0xFFL

    /**
     * Reads and decodes one frame from [source]. Returns [DecodeResult.EndOfStream] only when the
     * stream ends at a frame boundary (zero bytes read before EOF) — an orderly, non-error close
     * (SPEC.md #framing-and-envelope); any other EOF is [MalformedFrameReason.TRUNCATED].
     */
    suspend fun decodeFrame(source: FrameSource): DecodeResult {
        val prefixOutcome = readFully(source, LENGTH_PREFIX_BYTES)
        return when (prefixOutcome) {
            is ReadOutcome.Eof -> prefixEofResult(prefixOutcome.bytesRead)
            is ReadOutcome.Complete -> decodeBody(source, prefixOutcome.bytes)
        }
    }

    private fun prefixEofResult(bytesRead: Int): DecodeResult =
        if (bytesRead == 0) DecodeResult.EndOfStream else rejected(MalformedFrameReason.TRUNCATED)

    private suspend fun decodeBody(
        source: FrameSource,
        prefixBytes: ByteArray,
    ): DecodeResult {
        val length = beUnsignedInt32(prefixBytes)
        return when {
            length == 0L -> rejected(MalformedFrameReason.BAD_LENGTH)
            length > FrameEncoder.MAX_ENVELOPE_BYTES -> rejected(MalformedFrameReason.TOO_LARGE)
            else -> readEnvelope(source, length.toInt())
        }
    }

    private suspend fun readEnvelope(
        source: FrameSource,
        length: Int,
    ): DecodeResult {
        val outcome = readFully(source, length)
        return when (outcome) {
            is ReadOutcome.Eof -> rejected(MalformedFrameReason.TRUNCATED)
            is ReadOutcome.Complete -> parseEnvelope(outcome.bytes)
        }
    }

    private fun parseEnvelope(envelopeBytes: ByteArray): DecodeResult {
        val envelope =
            try {
                Envelope.parseFrom(envelopeBytes)
            } catch (_: InvalidProtocolBufferException) {
                return rejected(MalformedFrameReason.DECODE_FAILED)
            }
        return validate(envelope)
    }

    private fun validate(envelope: Envelope): DecodeResult =
        when {
            envelope.channel == Channel.UNRECOGNIZED || envelope.channel == Channel.CHANNEL_UNSPECIFIED -> {
                rejected(MalformedFrameReason.UNKNOWN_CHANNEL)
            }

            envelope.payloadCase == Envelope.PayloadCase.PAYLOAD_NOT_SET -> {
                rejected(MalformedFrameReason.UNKNOWN_PAYLOAD_TYPE)
            }

            else -> {
                DecodeResult.Frame(envelope)
            }
        }

    private fun rejected(reason: MalformedFrameReason): DecodeResult.Rejected =
        DecodeResult.Rejected(CloseCode.MALFORMED_FRAME, reason)

    private fun beUnsignedInt32(bytes: ByteArray): Long {
        var value = 0L
        for (byte in bytes) {
            value = (value shl BYTE_BITS) or (byte.toLong() and BYTE_MASK)
        }
        return value
    }

    /** Reads exactly [length] bytes from [source], or reports how many arrived before EOF. */
    private suspend fun readFully(
        source: FrameSource,
        length: Int,
    ): ReadOutcome {
        val buffer = ByteArray(length)
        var offset = 0
        while (offset < length) {
            val n = source.read(buffer, offset, length - offset)
            if (n <= 0) return ReadOutcome.Eof(offset)
            offset += n
        }
        return ReadOutcome.Complete(buffer)
    }

    private sealed class ReadOutcome {
        data class Complete(
            val bytes: ByteArray,
        ) : ReadOutcome()

        data class Eof(
            val bytesRead: Int,
        ) : ReadOutcome()
    }
}

/** Outcome of [FrameDecoder.decodeFrame]. */
sealed class DecodeResult {
    /** A well-formed frame, decoded to its [Envelope]. */
    data class Frame(
        val envelope: Envelope,
    ) : DecodeResult()

    /**
     * A framing-level protocol violation (SPEC.md #framing-and-envelope rejection-cases table):
     * the connection MUST close with [closeCode], [reason] being a local diagnostic only, never
     * sent on the wire.
     */
    data class Rejected(
        val closeCode: CloseCode,
        val reason: MalformedFrameReason,
    ) : DecodeResult()

    /**
     * The stream ended in an orderly way exactly at a frame boundary (zero bytes read before
     * EOF) — a normal connection close, not a violation (SPEC.md #framing-and-envelope).
     */
    data object EndOfStream : DecodeResult()
}

/**
 * Local diagnostic reasons grouped under [CloseCode.MALFORMED_FRAME] (SPEC.md
 * #framing-and-envelope rejection-cases table, #errors-and-close-codes). Never sent on the wire.
 */
enum class MalformedFrameReason {
    /** `length_prefix` > [FrameEncoder.MAX_ENVELOPE_BYTES], including the unsigned `0xFFFFFFFF`. */
    TOO_LARGE,

    /** `length_prefix` == 0. */
    BAD_LENGTH,

    /** The stream ended (EOF) after at least 1 byte of a new frame arrived but before it completed. */
    TRUNCATED,

    /** The `length_prefix` bytes were fully delivered but failed to decode as a well-formed `Envelope`. */
    DECODE_FAILED,

    /** `channel` is not one of the ten enumerated values (including the reserved `CHANNEL_UNSPECIFIED = 0`). */
    UNKNOWN_CHANNEL,

    /** The `oneof payload` is unset, or set to a payload type this receiver's protocol version does not define. */
    UNKNOWN_PAYLOAD_TYPE,

    /**
     * SPEC.md #framing-and-envelope "Sequence and acknowledgement violations" (`docs/planning/decisions.md`
     * D-57): a `seq` of 0, a `seq` at or below the current per-channel ack watermark, a duplicate of an
     * already-received above-watermark `seq`, or an `ack` above the highest `seq` this side has itself
     * sent on that channel. Detected by
     * [dev.tandem.core.protocol.multiplex.ChannelMultiplexer] (E11-05), never by [FrameDecoder] itself,
     * since it is a per-channel stateful check rather than a stateless framing check.
     */
    SEQ_REGRESSION,

    /**
     * A channel's above-watermark `seq` gap grew past
     * [dev.tandem.core.protocol.flowcontrol.CreditCaps.PROTOCOL_MAX] (D-64): a legitimate peer,
     * bound by its receive credit, can never have this many `seq` values outstanding above the
     * watermark at once, so this is a fatal violation rather than another accepted gap-fill.
     * Detected by [dev.tandem.core.protocol.multiplex.ChannelMultiplexer] (E11-05) alongside
     * [SEQ_REGRESSION].
     */
    SEQ_GAP_TOO_LARGE,
}
