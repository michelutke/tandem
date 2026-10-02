package dev.tandem.feature.contacts

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** PhoneNormalizer tests (E51-03; `docs/planning/backlog/phase-5.yaml` E51-03's `tdd:` list). */
class PhoneNormalizerTest {
    @Test
    fun phoneNormalizer_chRegionNationalVariants_allNormalizeToPlus41791234567() {
        val normalizer = PhoneNormalizer(RegionSource { "CH" })

        listOf("079 123 45 67", "0791234567", "+41 79 123 45 67", "0041791234567").forEach { raw ->
            assertEquals(NormalizedPhone(raw, "+41791234567"), normalizer.normalize(raw), raw)
        }
    }

    @Test
    fun phoneNormalizer_deRegionNationalNumber_normalizesToPlus49() {
        val normalizer = PhoneNormalizer(RegionSource { "DE" })

        assertEquals(NormalizedPhone("030 1234567", "+49301234567"), normalizer.normalize("030 1234567"))
    }

    @Test
    fun phoneNormalizer_unparsableInput_returnsRawWithNullE164() {
        val normalizer = PhoneNormalizer(RegionSource { "CH" })

        listOf("abc", "1234", "").forEach { raw ->
            val result = normalizer.normalize(raw)
            assertEquals(raw, result.raw)
            assertNull(result.normalizedE164, raw)
        }
    }

    @Test
    fun phoneNormalizer_alphanumericSenderId_returnsRawWithNullE164() {
        val normalizer = PhoneNormalizer(RegionSource { "CH" })

        listOf("Swisscom", "UBS-Alert", "1-800-FLOWERS").forEach { raw ->
            val result = normalizer.normalize(raw)
            assertEquals(raw, result.raw)
            assertNull(result.normalizedE164, raw)
        }
    }
}
