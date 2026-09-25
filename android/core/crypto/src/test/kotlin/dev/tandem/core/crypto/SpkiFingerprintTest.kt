package dev.tandem.core.crypto

import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.security.KeyPairGenerator
import java.security.spec.ECGenParameterSpec

/**
 * `spkiFingerprint` tests (E10-03). Vectors come from the committed E01-17 manifest
 * `protocol/vectors/spki-fingerprint.json` (path wired via the `tandem.vectorsDir` system
 * property, android/core/crypto/build.gradle.kts), not a duplicated test resource. Loading helpers
 * live in `SpkiFingerprintVectorTestSupport.kt`.
 */
class SpkiFingerprintTest {
    @Test
    fun spkiFingerprint_everyFingerprintVector_matchesExpectedSha256() {
        val vectors = loadSpkiFingerprintVectorsFile().getValue("vectors").jsonArray.map { it.jsonObject }
        val positiveVectors = vectors.filter { "expected" in it }
        assertTrue(positiveVectors.isNotEmpty(), "expected at least one positive spki-fingerprint vector")

        for (vector in positiveVectors) {
            val id = vector.getValue("id").jsonPrimitive.content
            val spkiDer =
                hexToBytes(
                    vector
                        .getValue("input")
                        .jsonObject
                        .getValue("spkiDerHex")
                        .jsonPrimitive.content,
                )
            val expectedHex =
                vector
                    .getValue("expected")
                    .jsonObject
                    .getValue("fingerprintHex")
                    .jsonPrimitive.content

            val fingerprint = spkiFingerprint(spkiDer)

            assertEquals(expectedHex, fingerprint.bytes.toHex(), id)
        }
    }

    @Test
    fun spkiFingerprint_rejectedVectors_throwsMatchingError() {
        val vectors = loadSpkiFingerprintVectorsFile().getValue("vectors").jsonArray.map { it.jsonObject }
        val negativeVectors = vectors.filter { "expectedError" in it }
        assertTrue(negativeVectors.isNotEmpty(), "expected at least one negative spki-fingerprint vector")

        for (vector in negativeVectors) {
            val id = vector.getValue("id").jsonPrimitive.content
            val spkiDer =
                hexToBytes(
                    vector
                        .getValue("input")
                        .jsonObject
                        .getValue("spkiDerHex")
                        .jsonPrimitive.content,
                )
            val expectedError = vector.getValue("expectedError").jsonPrimitive.content

            val thrown = assertThrows(SpkiFingerprintException::class.java, { spkiFingerprint(spkiDer) }, id)

            val actualError =
                when (thrown) {
                    is SpkiFingerprintException.UnsupportedPointEncoding -> "unsupportedPointEncoding"
                    is SpkiFingerprintException.UnsupportedKeyType -> "unsupportedKeyType"
                    is SpkiFingerprintException.MalformedSpki -> "malformedSpki"
                }
            assertEquals(expectedError, actualError, id)
        }
    }

    @Test
    fun spkiFingerprint_twoDecodesOfSameCert_identical32Bytes() {
        val spkiDer = generateP256Spki()

        val first = spkiFingerprint(spkiDer.copyOf())
        val second = spkiFingerprint(spkiDer.copyOf())

        assertEquals(32, first.bytes.size)
        assertTrue(first.bytes.contentEquals(second.bytes))
    }

    @Test
    fun spkiFingerprint_stringForm_is43CharsBase64UrlNoPadding() {
        val fingerprint = spkiFingerprint(generateP256Spki())

        assertEquals(43, fingerprint.base64Url.length)
        assertFalse(fingerprint.base64Url.contains("="))
        assertFalse(fingerprint.base64Url.contains("+"))
        assertFalse(fingerprint.base64Url.contains("/"))
    }

    @Test
    fun spkiFingerprint_differentPublicKey_differentFingerprint() {
        val first = spkiFingerprint(generateP256Spki())
        val second = spkiFingerprint(generateP256Spki())

        assertFalse(first.bytes.contentEquals(second.bytes))
    }

    private fun generateP256Spki(): ByteArray =
        KeyPairGenerator
            .getInstance("EC")
            .apply { initialize(ECGenParameterSpec("secp256r1")) }
            .generateKeyPair()
            .public
            .encoded
}
