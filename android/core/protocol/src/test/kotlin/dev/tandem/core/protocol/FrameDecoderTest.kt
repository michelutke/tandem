package dev.tandem.core.protocol

import dev.tandem.core.testing.InMemoryDuplexPipe
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.DeviceStatus
import dev.tandem.protocol.v1.Envelope
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.runInterruptible
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * FrameDecoder tests (E11-02). Vectors come from the same committed E01-19 manifest
 * `protocol/vectors/frame-encoding.json` [FrameEncoderTest] (E11-01) uses; loading and
 * recipe-reconstruction helpers live in `FrameVectorTestSupport.kt`, shared between the two.
 */
class FrameDecoderTest {
    @Test
    fun decodeFrame_everyValidFrameVector_decodesToExpectedEnvelope() =
        runBlocking {
            val validVectors =
                loadVectorsFile()
                    .getValue("vectors")
                    .jsonArray
                    .map { it.jsonObject }
                    .filter { "expected" in it }
            assertTrue(validVectors.isNotEmpty(), "expected at least one valid frame-encoding vector")

            for (vector in validVectors) {
                val id = vector.getValue("id").jsonPrimitive.content
                val input = vector.getValue("input").jsonObject
                val expected = vector.getValue("expected").jsonObject

                val envelopeBytes =
                    if ("frameHex" in input) {
                        val fullFrame = hexToBytes(input.getValue("frameHex").jsonPrimitive.content)
                        fullFrame.copyOfRange(LENGTH_PREFIX_BYTES, fullFrame.size)
                    } else {
                        buildEnvelopeFromRecipe(input.getValue("envelopeRecipe").jsonObject)
                    }
                // Re-encoded (not the raw frameHex) so the decoder is exercised against a frame
                // it did not itself produce the bytes of, while still matching the vector byte
                // for byte (FrameEncoder's own correctness is FrameEncoderTest's job, E11-01).
                val frameBytes = FrameEncoder.encodeFrame(Envelope.parseFrom(envelopeBytes))

                val result = FrameDecoder.decodeFrame(sourceFor(frameBytes))

                val frame = result as? DecodeResult.Frame ?: error("expected Frame for $id, got $result")
                assertEquals(expected.getValue("channel").jsonPrimitive.content, frame.envelope.channel.name, id)
                assertEquals(expected.getValue("seq").jsonPrimitive.long, frame.envelope.seq, id)
                assertEquals(expected.getValue("ack").jsonPrimitive.long, frame.envelope.ack, id)
                assertEquals(
                    payloadCaseFor(expected.getValue("payload").jsonPrimitive.content),
                    frame.envelope.payloadCase,
                    id,
                )
            }
        }

    @Test
    fun decodeFrame_everyInvalidFrameVector_rejectsWithExpectedCloseCodeAndReason() =
        runBlocking {
            val invalidVectors =
                loadVectorsFile()
                    .getValue("vectors")
                    .jsonArray
                    .map { it.jsonObject }
                    .filter { "expectedError" in it }
            assertTrue(invalidVectors.isNotEmpty(), "expected at least one invalid frame-encoding vector")

            for (vector in invalidVectors) {
                val id = vector.getValue("id").jsonPrimitive.content
                val frameBytes = frameHexBytes(vector)
                val pipe = InMemoryDuplexPipe(capacity = maxOf(frameBytes.size, 1))
                pipe.endpointA.output.write(frameBytes)
                pipe.endpointA.closeGracefully()

                val result = FrameDecoder.decodeFrame(sourceFor(pipe))

                val rejected = result as? DecodeResult.Rejected ?: error("expected Rejected for $id, got $result")
                assertEquals(vector.getValue("closeCode").jsonPrimitive.content, rejected.closeCode.name, id)
                assertEquals(vector.getValue("localReason").jsonPrimitive.content, rejected.reason.name, id)
            }
        }

    @Test
    fun decodeFrame_declaredLengthOver1MiB_closesTooLargeAfterPrefixOnly() =
        runBlocking {
            for (id in listOf("frame-oversize-plus-one", "frame-bad-length-0xffffffff")) {
                val vector = findVector(id)
                val prefixBytes = frameHexBytes(vector)
                assertEquals(LENGTH_PREFIX_BYTES, prefixBytes.size, id)
                val extraBytes = byteArrayOf(0x11, 0x22, 0x33)

                val pipe = InMemoryDuplexPipe(capacity = prefixBytes.size + extraBytes.size)
                pipe.endpointA.output.write(prefixBytes + extraBytes)

                val result = FrameDecoder.decodeFrame(sourceFor(pipe))

                assertEquals(
                    DecodeResult.Rejected(CloseCode.MALFORMED_FRAME, MalformedFrameReason.TOO_LARGE),
                    result,
                    id,
                )

                val remaining = ByteArray(extraBytes.size)
                val n = pipe.endpointB.input.read(remaining)
                assertEquals(extraBytes.size, n, "$id: only the 4 prefix bytes must be consumed")
                assertArrayEquals(extraBytes, remaining, id)
            }
        }

    @Test
    fun decodeFrame_declaredLengthZero_closesBadLength() =
        runBlocking {
            val vector = findVector("frame-bad-length-zero")
            val frameBytes = frameHexBytes(vector)
            val pipe = InMemoryDuplexPipe(capacity = frameBytes.size)
            pipe.endpointA.output.write(frameBytes)

            val result = FrameDecoder.decodeFrame(sourceFor(pipe))

            assertEquals(DecodeResult.Rejected(CloseCode.MALFORMED_FRAME, MalformedFrameReason.BAD_LENGTH), result)
        }

    @Test
    fun decodeFrame_eofMidPrefixOrPayload_closesTruncated() =
        runBlocking {
            // EOF mid length-prefix: 2 of the 4 prefix bytes arrive, then the connection closes.
            val midPrefixPipe = InMemoryDuplexPipe(capacity = 2)
            midPrefixPipe.endpointA.output.write(byteArrayOf(0x00, 0x00))
            midPrefixPipe.endpointA.closeGracefully()

            val midPrefixResult = FrameDecoder.decodeFrame(sourceFor(midPrefixPipe))

            assertEquals(
                DecodeResult.Rejected(CloseCode.MALFORMED_FRAME, MalformedFrameReason.TRUNCATED),
                midPrefixResult,
                "EOF mid length-prefix",
            )

            // EOF mid-payload: frame-truncated delivers 16 of the 17 declared envelope bytes.
            val vector = findVector("frame-truncated")
            val frameBytes = frameHexBytes(vector)
            val midPayloadPipe = InMemoryDuplexPipe(capacity = frameBytes.size)
            midPayloadPipe.endpointA.output.write(frameBytes)
            midPayloadPipe.endpointA.closeGracefully()

            val midPayloadResult = FrameDecoder.decodeFrame(sourceFor(midPayloadPipe))

            assertEquals(
                DecodeResult.Rejected(CloseCode.MALFORMED_FRAME, MalformedFrameReason.TRUNCATED),
                midPayloadResult,
                "EOF mid-payload",
            )
        }

    @Test
    fun decodeFrame_garbagePayload_closesDecodeFailedNoEnvelopeEmitted() =
        runBlocking {
            val vector = findVector("frame-decode-failed")
            val frameBytes = frameHexBytes(vector)
            val pipe = InMemoryDuplexPipe(capacity = frameBytes.size)
            pipe.endpointA.output.write(frameBytes)

            val result = FrameDecoder.decodeFrame(sourceFor(pipe))

            assertEquals(DecodeResult.Rejected(CloseCode.MALFORMED_FRAME, MalformedFrameReason.DECODE_FAILED), result)
        }

    @Test
    fun decodeFrame_unknownChannelValue_closesUnknownChannel() =
        runBlocking {
            val vector = findVector("frame-unknown-channel")
            val frameBytes = frameHexBytes(vector)
            val pipe = InMemoryDuplexPipe(capacity = frameBytes.size)
            pipe.endpointA.output.write(frameBytes)

            val result = FrameDecoder.decodeFrame(sourceFor(pipe))

            assertEquals(DecodeResult.Rejected(CloseCode.MALFORMED_FRAME, MalformedFrameReason.UNKNOWN_CHANNEL), result)
        }

    @Test
    fun decodeFrame_unknownPayloadTypeValue_closesUnknownPayloadType() =
        runBlocking {
            val vector = findVector("frame-unknown-payload-type")
            val frameBytes = frameHexBytes(vector)
            val pipe = InMemoryDuplexPipe(capacity = frameBytes.size)
            pipe.endpointA.output.write(frameBytes)

            val result = FrameDecoder.decodeFrame(sourceFor(pipe))

            assertEquals(
                DecodeResult.Rejected(CloseCode.MALFORMED_FRAME, MalformedFrameReason.UNKNOWN_PAYLOAD_TYPE),
                result,
            )
        }

    @Test
    fun decodeFrame_eofAtFrameBoundary_returnsEndOfStream() =
        runBlocking {
            // SPEC.md #framing-and-envelope: an orderly close with zero bytes into a new frame is
            // a normal connection close, not a TRUNCATED violation.
            val pipe = InMemoryDuplexPipe()
            pipe.endpointA.closeGracefully()

            val result = FrameDecoder.decodeFrame(sourceFor(pipe))

            assertEquals(DecodeResult.EndOfStream, result)
        }

    @Test
    fun decodeFrame_sourceReturnsOneBytePerRead_decodesIntoSingleBuffer() =
        runBlocking {
            val envelope =
                Envelope
                    .newBuilder()
                    .setChannel(Channel.CHANNEL_STATUS)
                    .setSeq(1)
                    .setDeviceStatus(DeviceStatus.getDefaultInstance())
                    .build()
            val frameBytes = FrameEncoder.encodeFrame(envelope)
            var position = 0
            val buffersSeen = mutableSetOf<Int>()
            val trickle =
                FrameSource { buffer, offset, _ ->
                    buffersSeen += System.identityHashCode(buffer)
                    if (position == frameBytes.size) {
                        -1
                    } else {
                        buffer[offset] = frameBytes[position++]
                        1
                    }
                }

            val result = FrameDecoder.decodeFrame(trickle)

            assertEquals(DecodeResult.Frame(envelope), result)
            // One buffer for the 4-byte prefix, one for the payload; never one per read.
            assertTrue(buffersSeen.size <= 2, "buffers allocated: ${buffersSeen.size}")
        }

    private companion object {
        fun findVector(id: String): JsonObject =
            loadVectorsFile()
                .getValue("vectors")
                .jsonArray
                .map { it.jsonObject }
                .first { it.getValue("id").jsonPrimitive.content == id }

        fun frameHexBytes(vector: JsonObject): ByteArray =
            hexToBytes(
                vector
                    .getValue("input")
                    .jsonObject
                    .getValue("frameHex")
                    .jsonPrimitive.content,
            )

        fun sourceFor(pipe: InMemoryDuplexPipe): FrameSource =
            FrameSource { buffer, offset, length ->
                runInterruptible { pipe.endpointB.input.read(buffer, offset, length) }
            }

        fun sourceFor(frameBytes: ByteArray): FrameSource {
            val pipe = InMemoryDuplexPipe(capacity = frameBytes.size)
            pipe.endpointA.output.write(frameBytes)
            return sourceFor(pipe)
        }
    }
}
