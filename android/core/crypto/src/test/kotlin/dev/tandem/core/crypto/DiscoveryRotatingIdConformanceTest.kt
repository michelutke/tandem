package dev.tandem.core.crypto

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * `DiscoveryRotatingId` conformance test (E21-05). Vectors come from the committed E01-20 manifest
 * `protocol/vectors/discovery-id.json` (path wired via the `tandem.vectorsDir` system property,
 * android/core/crypto/build.gradle.kts), not a duplicated test resource -- mirrors
 * `SpkiFingerprintTest`'s convention. Only the `kind == "computeId"` vectors are exercised here;
 * `recognition`/`txtRecord` kinds are exercised end-to-end by the conformance runner
 * (`core/pairing`'s `ConformanceRunnerTest`).
 */
class DiscoveryRotatingIdConformanceTest {
    @Test
    fun rotatingIdVectors_kotlinCodec_matchesExpectedIds() {
        val vectorsDirProperty =
            System.getProperty("tandem.vectorsDir") ?: error("tandem.vectorsDir system property not set")
        val manifest =
            Json
                .parseToJsonElement(File(vectorsDirProperty, "discovery-id.json").readText())
                .jsonObject
        val vectors = manifest.getValue("vectors").jsonArray.map { it.jsonObject }
        val computeIdVectors =
            vectors.filter { vector ->
                val kind =
                    vector
                        .getValue("input")
                        .jsonObject
                        .getValue("kind")
                        .jsonPrimitive.content
                kind == "computeId"
            }
        assertTrue(computeIdVectors.isNotEmpty(), "expected at least one computeId vector")

        for (vector in computeIdVectors) {
            val id = vector.getValue("id").jsonPrimitive.content
            val input = vector.getValue("input").jsonObject
            val fingerprint = hexToBytes(input.getValue("macSpkiFingerprintHex").jsonPrimitive.content)
            val unixSecondsUtc = input.getValue("unixSecondsUtc").jsonPrimitive.long
            val expected = vector.getValue("expected").jsonObject
            val expectedDayIndex = expected.getValue("dayIndex").jsonPrimitive.long
            val expectedIdHex = expected.getValue("idHex").jsonPrimitive.content

            val dayIndex = DiscoveryRotatingId.dayIndex(unixSecondsUtc)
            val idHex = DiscoveryRotatingId.computeHex(fingerprint, dayIndex)

            assertEquals(expectedDayIndex, dayIndex, id)
            assertEquals(expectedIdHex, idHex, id)
        }
    }
}
