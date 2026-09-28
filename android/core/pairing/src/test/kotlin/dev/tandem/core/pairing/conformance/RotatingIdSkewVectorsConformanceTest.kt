package dev.tandem.core.pairing.conformance

import dev.tandem.core.crypto.DiscoveryRotatingId
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.jupiter.api.Assertions.assertDoesNotThrow
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test
import java.io.File

/**
 * E21-07's own skew-boundary tdd names, distinct from [ConformanceRunnerTest]'s generic
 * everyVectorPasses sweep (which already exercises every `discovery-id.json` vector, including
 * these): pins down specifically that the `recognition`-kind skew vectors at dayIndex+/-1 are
 * recognized and dayIndex+/-2 are rejected, mirroring `RotatingIdSkewVectorsTests.swift` on
 * macOS -- "on both codecs" in the tdd name means this Kotlin test and that Swift test share a
 * name, each against its own platform's [DiscoveryRotatingId], not that this one file spans both.
 *
 * Invariant 3 (CLAUDE.md): recognition here is a connection-candidate hint only -- see
 * [dev.tandem.core.discovery.PairedMacMatcher]'s own kdoc. These tests assert only whether
 * [DiscoveryRotatingId.recognize] accepts/rejects a hex id; they never exercise or imply anything
 * about the mTLS pin check that alone establishes trust.
 */
class RotatingIdSkewVectorsConformanceTest {
    private data class RecognitionVector(
        val id: String,
        val pairedFingerprint: ByteArray,
        val receiverUnixSecondsUtc: Long,
        val advertisedFingerprint: ByteArray,
        val advertisedDayIndex: Long,
    )

    private fun recognitionVector(vectorId: String): RecognitionVector {
        val vectorsDirProperty =
            System.getProperty("tandem.vectorsDir") ?: error("tandem.vectorsDir system property not set")
        val manifest =
            Json
                .parseToJsonElement(File(vectorsDirProperty, "discovery-id.json").readText())
                .jsonObject
        val vector =
            manifest
                .getValue("vectors")
                .jsonArray
                .map { it.jsonObject }
                .single { it.getValue("id").jsonPrimitive.content == vectorId }
        val input = vector.getValue("input").jsonObject
        return RecognitionVector(
            id = vectorId,
            pairedFingerprint = hexToBytes(input.getValue("pairedMacSpkiFingerprintHex").jsonPrimitive.content),
            receiverUnixSecondsUtc = input.getValue("receiverUnixSecondsUtc").jsonPrimitive.long,
            advertisedFingerprint = hexToBytes(input.getValue("advertisedSpkiFingerprintHex").jsonPrimitive.content),
            advertisedDayIndex = input.getValue("advertisedDayIndex").jsonPrimitive.long,
        )
    }

    private fun assertRecognized(vectorId: String) {
        val vector = recognitionVector(vectorId)
        val candidateIdsHex =
            DiscoveryRotatingId.candidateHexIds(vector.pairedFingerprint, vector.receiverUnixSecondsUtc)
        val advertisedIdHex = DiscoveryRotatingId.computeHex(vector.advertisedFingerprint, vector.advertisedDayIndex)

        assertDoesNotThrow({ DiscoveryRotatingId.recognize(advertisedIdHex, candidateIdsHex) }, vector.id)
    }

    private fun assertRejected(vectorId: String) {
        val vector = recognitionVector(vectorId)
        val candidateIdsHex =
            DiscoveryRotatingId.candidateHexIds(vector.pairedFingerprint, vector.receiverUnixSecondsUtc)
        val advertisedIdHex = DiscoveryRotatingId.computeHex(vector.advertisedFingerprint, vector.advertisedDayIndex)

        assertThrows(
            DiscoveryRotatingId.RecognitionException.NotRecognized::class.java,
            { DiscoveryRotatingId.recognize(advertisedIdHex, candidateIdsHex) },
            vector.id,
        )
    }

    @Test
    fun rotatingIdSkewVectors_plusMinusOneDay_recognizedOnBothCodecs() {
        assertRecognized("discovery-id-skew-minus-one-recognized")
        assertRecognized("discovery-id-skew-plus-one-recognized")
    }

    @Test
    fun rotatingIdSkewVectors_plusMinusTwoDays_rejectedOnBothCodecs() {
        assertRejected("discovery-id-skew-minus-two-not-recognized")
        assertRejected("discovery-id-skew-plus-two-not-recognized")
    }
}
