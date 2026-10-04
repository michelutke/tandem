package dev.tandem.harness.jvmclient

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.RotationProof
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.protocol.v1.KeyRotation
import dev.tandem.protocol.v1.keyRotation
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/** E70-09: the phone-side check of the Mac's offered `KeyRotation` behind `RAWMACROTATION`. */
class RawMacRotationTest {
    private val macKey = newKeyPair()
    private val newKey = newKeyPair()
    private val challenge = RawMacRotation.newChallenge()

    @Test
    fun rawMacRotation_newChallenge_is32RandomBytes() {
        assertEquals(32, challenge.size)
        assertFalse(challenge.contentEquals(RawMacRotation.newChallenge()))
    }

    @Test
    fun rawMacRotation_offerSignedByMacKeyAndNewKeyOverChallenge_isValid() {
        assertTrue(RawMacRotation.isValidOffer(macKey.public.encoded, challenge, offer(challenge)))
    }

    @Test
    fun rawMacRotation_offerBuiltOverOtherChallenge_isInvalid() {
        assertFalse(RawMacRotation.isValidOffer(macKey.public.encoded, challenge, offer(RawMacRotation.newChallenge())))
    }

    @Test
    fun rawMacRotation_offerFromKeyThatDidNotAuthenticateSession_isInvalid() {
        assertFalse(RawMacRotation.isValidOffer(newKeyPair().public.encoded, challenge, offer(challenge)))
    }

    @Test
    fun rawMacRotation_newKeyFingerprintHex_matchesSpkiFingerprintOfNewKey() {
        val expected = spkiFingerprint(newKey.public.encoded).bytes.joinToString(separator = "") { "%02x".format(it) }

        assertEquals(expected, RawMacRotation.newKeyFingerprintHex(offer(challenge)))
    }

    private fun offer(cb: ByteArray): KeyRotation {
        val transcript = RotationProof.transcript(macKey.public.encoded, newKey.public.encoded, cb)
        return keyRotation {
            newSpkiDer = ByteString.copyFrom(newKey.public.encoded)
            sigOldKey = ByteString.copyFrom(sign(macKey, transcript))
            sigNewKey = ByteString.copyFrom(sign(newKey, transcript))
        }
    }

    private fun sign(
        key: KeyPair,
        message: ByteArray,
    ): ByteArray =
        Signature.getInstance("SHA256withECDSA").run {
            initSign(key.private)
            update(message)
            sign()
        }

    private fun newKeyPair(): KeyPair =
        KeyPairGenerator.getInstance("EC").run {
            initialize(ECGenParameterSpec("secp256r1"))
            generateKeyPair()
        }
}
