package dev.tandem.core.protocol

import dev.tandem.protocol.v1.Envelope

/**
 * FrameEncoder (E11-01): writes the wire frame docs/protocol/SPEC.md #framing-and-envelope
 * defines as `frame = length_prefix envelope_bytes` — a 4-byte big-endian length prefix (the
 * serialized [Envelope]'s byte count, excluding the prefix itself) followed by the serialized
 * [Envelope]. Returns a plain [ByteArray]: this module has no dependency on the `ByteStream` seam
 * (core/transport), so callers write the result to a `ByteStream`'s `OutputStream` themselves.
 */
object FrameEncoder {
    /** SPEC.md #framing-and-envelope: the maximum serialized Envelope length, in bytes. */
    const val MAX_ENVELOPE_BYTES: Int = 1_048_576

    private const val LENGTH_PREFIX_BYTES = 4
    private const val BYTE_BITS = 8
    private const val BYTE_MASK = 0xFF

    /**
     * Encodes [envelope] as a length-prefixed frame. Throws [FrameTooLargeException] (with
     * nothing written, since this returns a single [ByteArray] rather than writing incrementally)
     * when the serialized Envelope exceeds [MAX_ENVELOPE_BYTES]; exactly [MAX_ENVELOPE_BYTES] is
     * accepted.
     */
    fun encodeFrame(envelope: Envelope): ByteArray {
        val envelopeBytes = envelope.toByteArray()
        if (envelopeBytes.size > MAX_ENVELOPE_BYTES) {
            throw FrameTooLargeException(envelopeBytes.size)
        }

        val frame = ByteArray(LENGTH_PREFIX_BYTES + envelopeBytes.size)
        for (index in 0 until LENGTH_PREFIX_BYTES) {
            val shift = BYTE_BITS * (LENGTH_PREFIX_BYTES - 1 - index)
            frame[index] = ((envelopeBytes.size ushr shift) and BYTE_MASK).toByte()
        }
        envelopeBytes.copyInto(destination = frame, destinationOffset = LENGTH_PREFIX_BYTES)
        return frame
    }
}

/**
 * Thrown by [FrameEncoder.encodeFrame] when the serialized Envelope's length exceeds
 * [FrameEncoder.MAX_ENVELOPE_BYTES] (SPEC.md #framing-and-envelope).
 */
class FrameTooLargeException(
    val envelopeLength: Int,
) : Exception(
        "Envelope length $envelopeLength exceeds max ${FrameEncoder.MAX_ENVELOPE_BYTES} bytes " +
            "(SPEC.md #framing-and-envelope)",
    )
