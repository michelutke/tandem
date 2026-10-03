package dev.tandem.feature.contacts

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * Runs `protocol/vectors/phone-normalization.json` (E51-06) through the production [PhoneNormalizer];
 * macOS's TandemStore `PhoneNormalizationVectorsTests` runs the same file through PhoneNumberKit.
 */
class PhoneNormalizationVectorsTest {
    @Test
    fun phoneNormalizationVectors_validCases_identicalE164BothPlatforms() {
        val valid = vectors().filter { it.expectedE164 != null }

        assertTrue(valid.isNotEmpty())
        valid.forEach { vector ->
            assertEquals(vector.expectedE164, normalize(vector), vector.id)
        }
    }

    @Test
    fun phoneNormalizationVectors_invalidCases_nullE164BothPlatforms() {
        val invalid = vectors().filter { it.expectedE164 == null }

        assertTrue(invalid.isNotEmpty())
        invalid.forEach { vector ->
            assertNull(normalize(vector), vector.id)
        }
    }

    private fun normalize(vector: PhoneVector): String? =
        PhoneNormalizer(RegionSource { vector.region }).normalize(vector.raw).normalizedE164

    private data class PhoneVector(
        val id: String,
        val raw: String,
        val region: String,
        val expectedE164: String?,
    )

    private fun vectors(): List<PhoneVector> {
        val dir = System.getProperty("tandem.vectorsDir") ?: error("tandem.vectorsDir system property not set")
        val manifest = Json.parseToJsonElement(File(dir, "phone-normalization.json").readText()).jsonObject
        return manifest.getValue("vectors").jsonArray.map { element ->
            val vector = element.jsonObject
            val input = vector.getValue("input").jsonObject
            PhoneVector(
                id = vector.getValue("id").jsonPrimitive.content,
                raw = input.getValue("raw").jsonPrimitive.content,
                region = input.getValue("region").jsonPrimitive.content,
                expectedE164 = vector.e164(),
            )
        }
    }

    private fun JsonObject.e164(): String? {
        val value = getValue("expected").jsonObject.getValue("e164")
        return if (value is JsonNull) null else value.jsonPrimitive.content
    }
}
