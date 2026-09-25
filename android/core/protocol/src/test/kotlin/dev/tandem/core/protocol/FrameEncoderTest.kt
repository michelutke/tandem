package dev.tandem.core.protocol

import dev.tandem.core.testing.InMemoryDuplexPipe
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
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
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest

/**
 * FrameEncoder tests (E11-01). Vectors come from the committed E01-19 manifest
 * `protocol/vectors/frame-encoding.json` (path wired via the `tandem.vectorsDir` system property,
 * android/core/protocol/build.gradle.kts), not a duplicated test resource.
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

    private companion object {
        const val LENGTH_PREFIX_BYTES = 4
        const val CHANNEL_FIELD_NUMBER = 1
        const val SEQ_FIELD_NUMBER = 2
        const val ACK_FIELD_NUMBER = 3
        const val RING_FIELD_NUMBER = 21
        const val FILLER_FIELD_NUMBER = 500_000
        const val RECIPE_SOLVE_ITERATIONS = 16

        fun loadVectorsFile(): JsonObject {
            val vectorsDir =
                System.getProperty("tandem.vectorsDir") ?: error("tandem.vectorsDir system property not set")
            val file = File(vectorsDir, "frame-encoding.json")
            return Json.parseToJsonElement(file.readText()).jsonObject
        }

        fun payloadCaseFor(kind: String): Envelope.PayloadCase =
            when (kind) {
                "ring" -> Envelope.PayloadCase.RING
                "deviceStatus" -> Envelope.PayloadCase.DEVICE_STATUS
                else -> error("unsupported payload kind: $kind")
            }

        fun hexToBytes(hex: String): ByteArray =
            ByteArray(hex.length / 2) { i -> hex.substring(i * 2, i * 2 + 2).toInt(16).toByte() }

        fun sha256Hex(bytes: ByteArray): String =
            MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

        // --- minimal protobuf wire-format encoder, mirroring tools/vectors/frame_encoding.py ---

        fun varint(value: Long): ByteArray {
            require(value >= 0) { "varint must be non-negative" }
            val out = ByteArrayOutputStream()
            var remaining = value
            while (true) {
                val byte = (remaining and 0x7F).toInt()
                remaining = remaining ushr 7
                if (remaining != 0L) {
                    out.write(byte or 0x80)
                } else {
                    out.write(byte)
                    return out.toByteArray()
                }
            }
        }

        fun tag(
            fieldNumber: Int,
            wireType: Int,
        ): ByteArray = varint((fieldNumber.toLong() shl 3) or wireType.toLong())

        fun fieldVarint(
            fieldNumber: Int,
            value: Long,
        ): ByteArray = tag(fieldNumber, 0) + varint(value)

        fun fieldLenDelimited(
            fieldNumber: Int,
            payload: ByteArray,
        ): ByteArray = tag(fieldNumber, 2) + varint(payload.size.toLong()) + payload

        /** Reconstructs the exact bytes a manifest `envelopeRecipe` describes (protocol/vectors/README.md). */
        fun buildEnvelopeFromRecipe(recipe: JsonObject): ByteArray {
            val out = ByteArrayOutputStream()
            val channel = Channel.valueOf(recipe.getValue("channel").jsonPrimitive.content)
            out.write(fieldVarint(CHANNEL_FIELD_NUMBER, channel.number.toLong()))

            val seq = recipe["seq"]?.jsonPrimitive?.long ?: 0L
            if (seq != 0L) out.write(fieldVarint(SEQ_FIELD_NUMBER, seq))
            val ack = recipe["ack"]?.jsonPrimitive?.long ?: 0L
            if (ack != 0L) out.write(fieldVarint(ACK_FIELD_NUMBER, ack))

            recipe["payload"]?.jsonObject?.let { payload ->
                val kind = payload.getValue("kind").jsonPrimitive.content
                require(kind == "ring") { "unsupported recipe payload kind: $kind" }
                out.write(fieldLenDelimited(RING_FIELD_NUMBER, ByteArray(0)))
            }

            recipe["filler"]?.jsonObject?.let { filler ->
                val fieldNumber = filler.getValue("fieldNumber").jsonPrimitive.int
                val fillByte =
                    filler
                        .getValue("fillByte")
                        .jsonPrimitive.content
                        .toInt(16)
                        .toByte()
                val fillLength = filler.getValue("fillLength").jsonPrimitive.int
                out.write(fieldLenDelimited(fieldNumber, ByteArray(fillLength) { fillByte }))
            }

            return out.toByteArray()
        }

        /** Inverse of tools/vectors/frame_encoding.py's `solve_filler`: a filler field padding a
         * minimal Envelope out to exactly [targetTotal] bytes. */
        fun solveFillerLength(
            fixedOverhead: Int,
            targetTotal: Int,
            fieldNumber: Int,
        ): Int {
            val tagLength = tag(fieldNumber, 2).size
            var varintLengthGuess = 1
            repeat(RECIPE_SOLVE_ITERATIONS) {
                val fillLength = targetTotal - fixedOverhead - tagLength - varintLengthGuess
                require(fillLength >= 0) { "target total too small for the fixed overhead and filler tag" }
                val actualLength = varint(fillLength.toLong()).size
                if (actualLength == varintLengthGuess) return fillLength
                varintLengthGuess = actualLength
            }
            error("failed to converge on a filler length")
        }

        /** A minimal Envelope (channel, seq, empty Ring payload) padded with an unrecognized
         * filler field to exactly [targetTotal] bytes, for tests that need a precise envelope size. */
        fun buildEnvelopeWithFiller(
            channel: Channel,
            seq: Long,
            targetTotal: Int,
            fillerFieldNumber: Int,
        ): ByteArray {
            val base = ByteArrayOutputStream()
            base.write(fieldVarint(CHANNEL_FIELD_NUMBER, channel.number.toLong()))
            if (seq != 0L) base.write(fieldVarint(SEQ_FIELD_NUMBER, seq))
            base.write(fieldLenDelimited(RING_FIELD_NUMBER, ByteArray(0)))
            val baseBytes = base.toByteArray()

            val fillLength = solveFillerLength(baseBytes.size, targetTotal, fillerFieldNumber)
            val filler = fieldLenDelimited(fillerFieldNumber, ByteArray(fillLength))
            return baseBytes + filler
        }
    }
}
