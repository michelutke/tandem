package dev.tandem.core.protocol

import dev.tandem.core.testing.InMemoryDuplexPipe
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * FrameEncoder tests (E11-01). Vectors come from the committed E01-19 manifest
 * `protocol/vectors/frame-encoding.json` (path wired via the `tandem.vectorsDir` system property,
 * android/core/protocol/build.gradle.kts), not a duplicated test resource. Loading and
 * recipe-reconstruction helpers live in `FrameVectorTestSupport.kt`, shared with
 * [FrameDecoderTest] (E11-02).
 */
class FrameEncoderTest {
    @Test
    fun encodeFrame_everyValidFrameVector_bytesEqualExpected() {
        val validVectors =
            loadVectorsFile().getValue("vectors").jsonArray.map { it.jsonObject }.filter {
                "expected" in
                    it
            }
        assertTrue(validVectors.isNotEmpty(), "expected at least one valid frame-encoding vector")

        for (vector in validVectors) {
            val id = vector.getValue("id").jsonPrimitive.content
            val input = vector.getValue("input").jsonObject
            val expected = vector.getValue("expected").jsonObject

            val fullFrame =
                if ("frameHex" in
                    input
                ) {
                    hexToBytes(input.getValue("frameHex").jsonPrimitive.content)
                } else {
                    null
                }
            val envelopeBytes =
                fullFrame?.copyOfRange(LENGTH_PREFIX_BYTES, fullFrame.size)
                    ?: buildEnvelopeFromRecipe(input.getValue("envelopeRecipe").jsonObject)
            assertEquals(expected.getValue("envelopeLength").jsonPrimitive.int, envelopeBytes.size, id)

            val envelope = Envelope.parseFrom(envelopeBytes)
            assertEquals(expected.getValue("channel").jsonPrimitive.content, envelope.channel.name, id)
            assertEquals(expected.getValue("seq").jsonPrimitive.long, envelope.seq, id)
            assertEquals(expected.getValue("ack").jsonPrimitive.long, envelope.ack, id)
            assertEquals(payloadCaseFor(expected.getValue("payload").jsonPrimitive.content), envelope.payloadCase, id)

            val pipe = InMemoryDuplexPipe(capacity = envelopeBytes.size + LENGTH_PREFIX_BYTES)
            pipe.endpointA.output.write(FrameEncoder.encodeFrame(envelope))
            val frame = pipe.capturedAToB()

            if (fullFrame != null) assertArrayEquals(fullFrame, frame, id)
            val frameSha256 = expected["frameSha256"]?.jsonPrimitive?.content
            if (frameSha256 != null) assertEquals(frameSha256, sha256Hex(frame), id)
        }
    }

    @Test
    fun encodeFrame_lengthPrefix_isBigEndianEnvelopeByteCount() {
        // Distinct, non-zero bytes at every position: a little-endian bug would fail this.
        val targetEnvelopeLength = 0x00_01_02_03
        val envelopeBytes =
            buildEnvelopeWithFiller(
                channel = Channel.CHANNEL_STATUS,
                seq = 1,
                targetTotal = targetEnvelopeLength,
                fillerFieldNumber = FILLER_FIELD_NUMBER,
            )
        assertEquals(targetEnvelopeLength, envelopeBytes.size)
        val envelope = Envelope.parseFrom(envelopeBytes)

        val pipe = InMemoryDuplexPipe(capacity = targetEnvelopeLength + LENGTH_PREFIX_BYTES)
        pipe.endpointA.output.write(FrameEncoder.encodeFrame(envelope))
        val frame = pipe.capturedAToB()

        assertArrayEquals(byteArrayOf(0x00, 0x01, 0x02, 0x03), frame.copyOfRange(0, LENGTH_PREFIX_BYTES))
        assertEquals(targetEnvelopeLength, frame.size - LENGTH_PREFIX_BYTES)
    }

    @Test
    fun encodeFrame_envelopeExactly1MiB_written() {
        val envelopeBytes =
            buildEnvelopeWithFiller(
                channel = Channel.CHANNEL_STATUS,
                seq = 1,
                targetTotal = FrameEncoder.MAX_ENVELOPE_BYTES,
                fillerFieldNumber = FILLER_FIELD_NUMBER,
            )
        assertEquals(FrameEncoder.MAX_ENVELOPE_BYTES, envelopeBytes.size)
        val envelope = Envelope.parseFrom(envelopeBytes)

        val pipe = InMemoryDuplexPipe(capacity = FrameEncoder.MAX_ENVELOPE_BYTES + LENGTH_PREFIX_BYTES)
        pipe.endpointA.output.write(FrameEncoder.encodeFrame(envelope))

        assertEquals(FrameEncoder.MAX_ENVELOPE_BYTES + LENGTH_PREFIX_BYTES, pipe.capturedAToB().size)
    }

    @Test
    fun encodeFrame_envelopeOneByteOver1MiB_throwsWithZeroBytesWritten() {
        val envelopeBytes =
            buildEnvelopeWithFiller(
                channel = Channel.CHANNEL_STATUS,
                seq = 1,
                targetTotal = FrameEncoder.MAX_ENVELOPE_BYTES + 1,
                fillerFieldNumber = FILLER_FIELD_NUMBER,
            )
        val envelope = Envelope.parseFrom(envelopeBytes)
        val pipe = InMemoryDuplexPipe()

        val exception =
            assertThrows(FrameTooLargeException::class.java) {
                pipe.endpointA.output.write(FrameEncoder.encodeFrame(envelope))
            }

        assertEquals(FrameEncoder.MAX_ENVELOPE_BYTES + 1, exception.envelopeLength)
        assertEquals(0, pipe.capturedAToB().size)
    }
}
