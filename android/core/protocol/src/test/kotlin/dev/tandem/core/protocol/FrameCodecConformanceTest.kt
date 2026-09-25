package dev.tandem.core.protocol

import dev.tandem.core.testing.InMemoryDuplexPipe
import dev.tandem.protocol.v1.Envelope
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.DynamicTest.dynamicTest
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.TestFactory

/**
 * E11-11: the codec-level conformance suite the future `tools/conformance` runner (E15-01/E15-03)
 * aggregates. Every entry in the committed E01-19 manifest `protocol/vectors/frame-encoding.json`
 * is exercised through the published [FrameEncoder]/[FrameDecoder] API, one JUnit dynamic test per
 * vector `id` — so each fixture is its own pass/fail line in the JUnit XML report, and adding a
 * fixture to the manifest changes the executed-case count without any change here. Loading and
 * recipe-reconstruction helpers are shared with [FrameEncoderTest] (E11-01) / [FrameDecoderTest]
 * (E11-02) via `FrameVectorTestSupport.kt`.
 */
@Tag("conformance")
class FrameCodecConformanceTest {
    @TestFactory
    fun kotlinFrameCodec_everyValidFrameVector_roundTripsToVectorBytes(): List<DynamicTest> {
        val validVectors =
            loadVectorsFile()
                .getValue("vectors")
                .jsonArray
                .map { it.jsonObject }
                .filter { "expected" in it }
        return validVectors.map { vector ->
            val id = vector.getValue("id").jsonPrimitive.content
            dynamicTest(id) { roundTripsToVectorBytes(vector) }
        }
    }

    private fun roundTripsToVectorBytes(vector: JsonObject) =
        runBlocking {
            val id = vector.getValue("id").jsonPrimitive.content
            val input = vector.getValue("input").jsonObject
            val expected = vector.getValue("expected").jsonObject

            val inputFrame =
                if ("frameHex" in input) {
                    hexToBytes(input.getValue("frameHex").jsonPrimitive.content)
                } else {
                    val envelopeBytes = buildEnvelopeFromRecipe(input.getValue("envelopeRecipe").jsonObject)
                    FrameEncoder.encodeFrame(Envelope.parseFrom(envelopeBytes))
                }

            val decoded = FrameDecoder.decodeFrame(sourceFor(inputFrame))
            val frame = decoded as? DecodeResult.Frame ?: error("expected Frame for $id, got $decoded")
            val outputFrame = FrameEncoder.encodeFrame(frame.envelope)

            if ("frameHex" in input) {
                assertArrayEquals(inputFrame, outputFrame, id)
            }
            val frameSha256 = expected["frameSha256"]?.jsonPrimitive?.content
            if (frameSha256 != null) assertEquals(frameSha256, sha256Hex(outputFrame), id)
        }

    @TestFactory
    fun kotlinFrameCodec_everyInvalidFrameVector_rejectedWithTaggedCloseCode(): List<DynamicTest> {
        val invalidVectors =
            loadVectorsFile()
                .getValue("vectors")
                .jsonArray
                .map { it.jsonObject }
                .filter { "expectedError" in it }
        return invalidVectors.map { vector ->
            val id = vector.getValue("id").jsonPrimitive.content
            dynamicTest(id) { rejectedWithTaggedCloseCode(vector) }
        }
    }

    private fun rejectedWithTaggedCloseCode(vector: JsonObject) =
        runBlocking {
            val id = vector.getValue("id").jsonPrimitive.content
            val frameBytes =
                hexToBytes(
                    vector
                        .getValue("input")
                        .jsonObject
                        .getValue("frameHex")
                        .jsonPrimitive.content,
                )
            val pipe = InMemoryDuplexPipe(capacity = maxOf(frameBytes.size, 1))
            pipe.endpointA.output.write(frameBytes)
            pipe.endpointA.closeGracefully()

            val result = FrameDecoder.decodeFrame(sourceFor(pipe))

            val rejected = result as? DecodeResult.Rejected ?: error("expected Rejected for $id, got $result")
            assertEquals(vector.getValue("closeCode").jsonPrimitive.content, rejected.closeCode.name, id)
            assertEquals(vector.getValue("localReason").jsonPrimitive.content, rejected.reason.name, id)
        }
}
