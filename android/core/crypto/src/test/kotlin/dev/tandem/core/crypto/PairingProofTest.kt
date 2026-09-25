package dev.tandem.core.crypto

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * `PairingProof`/`ConfirmationCode` tests (E10-12). Vectors come from the committed E01-18
 * manifest `protocol/vectors/pairing-proof.json` (path wired via the `tandem.vectorsDir` system
 * property, android/core/crypto/build.gradle.kts), not a duplicated test resource. Loading helpers
 * live in `PairingProofVectorTestSupport.kt`.
 */
class PairingProofTest {
    @Test
    fun pairingProof_everyHmacVector_matchesExpectedProof() {
        val vectors = proofVectors()
        assertTrue(vectors.isNotEmpty(), "expected at least one pairing-proof vector")

        for (vector in vectors) {
            val id = vector.getValue("id").jsonPrimitive.content
            val secret = secretOf(vector)
            val macSpkiDer = macSpkiDerOf(vector)
            val phoneSpkiDer = phoneSpkiDerOf(vector)
            val cb = cbOf(vector)
            val proof = proofOf(vector)

            if ("expected" in vector) {
                assertTrue(PairingProof.verify(proof, secret, macSpkiDer, phoneSpkiDer, cb), id)
            } else {
                when (val expectedError = vector.getValue("expectedError").jsonPrimitive.content) {
                    "proofMismatch" -> {
                        assertFalse(PairingProof.verify(proof, secret, macSpkiDer, phoneSpkiDer, cb), id)
                    }

                    "malformedProof" -> {
                        assertThrows(PairingProofException.MalformedProof::class.java, {
                            PairingProof.verify(proof, secret, macSpkiDer, phoneSpkiDer, cb)
                        }, id)
                    }

                    "malformedSpki" -> {
                        assertThrows(PairingProofException.MalformedSpki::class.java, {
                            PairingProof.verify(proof, secret, macSpkiDer, phoneSpkiDer, cb)
                        }, id)
                    }

                    else -> {
                        error("unexpected expectedError $expectedError for vector $id")
                    }
                }
            }
        }
    }

    @Test
    fun pairingProof_secretOneBitFlipped_outputDiffers() {
        val vector = firstPositiveProofVector()
        val secret = secretOf(vector)
        val macSpkiDer = macSpkiDerOf(vector)
        val phoneSpkiDer = phoneSpkiDerOf(vector)
        val cb = cbOf(vector)

        val flippedSecret = secret.copyOf().also { it[0] = (it[0].toInt() xor 0x01).toByte() }

        val proof = PairingProof.compute(secret, macSpkiDer, phoneSpkiDer, cb)
        val flippedProof = PairingProof.compute(flippedSecret, macSpkiDer, phoneSpkiDer, cb)

        assertFalse(proof.contentEquals(flippedProof))
    }

    @Test
    fun pairingProof_macAndPhoneSpkiSwapped_outputDiffers() {
        val vector = firstPositiveProofVector()
        val secret = secretOf(vector)
        val macSpkiDer = macSpkiDerOf(vector)
        val phoneSpkiDer = phoneSpkiDerOf(vector)
        val cb = cbOf(vector)

        val proof = PairingProof.compute(secret, macSpkiDer, phoneSpkiDer, cb)
        val swappedProof = PairingProof.compute(secret, phoneSpkiDer, macSpkiDer, cb)

        assertFalse(proof.contentEquals(swappedProof))
    }

    @Test
    fun pairingCode_everyCodeVector_matchesExpectedSixDigits() {
        val vectors = codeVectors()
        assertTrue(vectors.isNotEmpty(), "expected at least one confirmation-code vector")

        for (vector in vectors) {
            val id = vector.getValue("id").jsonPrimitive.content
            val secret = secretOf(vector)
            val macSpkiDer = macSpkiDerOf(vector)
            val phoneSpkiDer = phoneSpkiDerOf(vector)
            val cb = cbOf(vector)
            val expectedCode =
                vector
                    .getValue("expected")
                    .jsonObject
                    .getValue("code")
                    .jsonPrimitive.content

            val code = ConfirmationCode.compute(secret, macSpkiDer, phoneSpkiDer, cb)

            assertEquals(6, code.length, id)
            assertEquals(expectedCode, code, id)
        }
    }

    @Test
    fun pairingProof_cbNot32Bytes_rejectedBeforeHmac() {
        val vector = firstPositiveProofVector()
        val secret = secretOf(vector)
        val macSpkiDer = macSpkiDerOf(vector)
        val phoneSpkiDer = phoneSpkiDerOf(vector)
        val truncatedCb = cbOf(vector).copyOf(31)

        assertThrows(PairingProofException.MalformedChannelBinding::class.java) {
            PairingProof.compute(secret, macSpkiDer, phoneSpkiDer, truncatedCb)
        }
    }

    private fun firstPositiveProofVector(): JsonObject = proofVectors().first { "expected" in it }

    private fun secretOf(vector: JsonObject): ByteArray = inputHex(vector, "secretHex")

    private fun macSpkiDerOf(vector: JsonObject): ByteArray = inputHex(vector, "macSpkiDerHex")

    private fun phoneSpkiDerOf(vector: JsonObject): ByteArray = inputHex(vector, "phoneSpkiDerHex")

    private fun cbOf(vector: JsonObject): ByteArray = inputHex(vector, "cbHex")

    private fun proofOf(vector: JsonObject): ByteArray = inputHex(vector, "proofHex")

    private fun inputHex(
        vector: JsonObject,
        field: String,
    ): ByteArray =
        hexToBytes(
            vector
                .getValue("input")
                .jsonObject
                .getValue(field)
                .jsonPrimitive.content,
        )
}
