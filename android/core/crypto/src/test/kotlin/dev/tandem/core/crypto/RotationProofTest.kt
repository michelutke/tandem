package dev.tandem.core.crypto

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.spec.ECGenParameterSpec

class RotationProofTest {
    private val oldKey = generate("secp256r1")
    private val newKey = generate("secp256r1")
    private val cb = ByteArray(32) { it.toByte() }

    private fun generate(curve: String): KeyPair =
        KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec(curve)) }.generateKeyPair()

    private fun sign(
        key: KeyPair,
        message: ByteArray,
    ): ByteArray =
        Signature.getInstance("SHA256withECDSA").run {
            initSign(key.private)
            update(message)
            sign()
        }

    private fun transcript(challenge: ByteArray = cb) =
        RotationProof.transcript(oldKey.public.encoded, newKey.public.encoded, challenge)

    @Test
    fun rotationProof_transcript_labelThenLengthPrefixedSpkisAndCb() {
        val transcript = transcript()

        assertEquals("tandem-rotate-v1", String(transcript.copyOfRange(0, 16), Charsets.US_ASCII))
        assertEquals(16 + 2 + 91 + 2 + 91 + 2 + 32, transcript.size)
    }

    @Test
    fun rotationProof_bothSignaturesOverTranscript_verifies() {
        val message = transcript()

        assertTrue(
            RotationProof.verify(
                oldKey.public.encoded,
                newKey.public.encoded,
                cb,
                sign(oldKey, message),
                sign(newKey, message),
            ),
        )
    }

    @Test
    fun rotationProof_signedOverOtherChallenge_fails() {
        val message = transcript(ByteArray(32) { 1 })

        assertFalse(
            RotationProof.verify(
                oldKey.public.encoded,
                newKey.public.encoded,
                cb,
                sign(oldKey, message),
                sign(newKey, message),
            ),
        )
    }

    @Test
    fun rotationProof_newKeySignatureByOtherKey_fails() {
        val message = transcript()

        assertFalse(
            RotationProof.verify(
                oldKey.public.encoded,
                newKey.public.encoded,
                cb,
                sign(oldKey, message),
                sign(oldKey, message),
            ),
        )
    }

    @Test
    fun rotationProof_shortChallengeOrGarbageSignature_failsWithoutThrowing() {
        val message = transcript()

        assertFalse(
            RotationProof.verify(
                oldKey.public.encoded,
                newKey.public.encoded,
                ByteArray(31),
                ByteArray(70),
                ByteArray(70),
            ),
        )
        assertFalse(
            RotationProof.verify(
                oldKey.public.encoded,
                newKey.public.encoded,
                cb,
                sign(oldKey, message),
                byteArrayOf(1),
            ),
        )
    }

    @Test
    fun rotationProof_p384NewKey_notStrictSpkiAndFails() {
        val p384 = generate("secp384r1")
        val message = RotationProof.transcript(oldKey.public.encoded, p384.public.encoded, cb)

        assertFalse(RotationProof.isStrictP256Spki(p384.public.encoded))
        assertFalse(
            RotationProof.verify(
                oldKey.public.encoded,
                p384.public.encoded,
                cb,
                sign(oldKey, message),
                sign(p384, message),
            ),
        )
    }
}
