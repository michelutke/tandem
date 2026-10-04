package dev.tandem.core.crypto

import java.security.GeneralSecurityException
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec

private const val ROTATE_LABEL = "tandem-rotate-v1"

/** SPEC.md #key-rotation: `cb` is exactly the 32 bytes of the receiver's `RotationChallenge`. */
const val ROTATION_CHALLENGE_LENGTH = 32

/**
 * SPEC.md #key-rotation "Transcript and signatures": `transcript = ASCII("tandem-rotate-v1") ||
 * LP(oldSpkiDer) || LP(newSpkiDer) || LP(cb)`, signed (ECDSA P-256 / SHA-256, ASN.1 DER) by both
 * the old key (authorizes) and the new key (proves possession). Consumed by E70-04.
 */
object RotationProof {
    /** True iff [spkiDer] is exactly a 91-byte uncompressed ECDSA P-256 SubjectPublicKeyInfo. */
    @Suppress("SwallowedException")
    fun isStrictP256Spki(spkiDer: ByteArray): Boolean =
        try {
            spkiFingerprint(spkiDer)
            true
        } catch (e: SpkiFingerprintException) {
            false
        }

    /**
     * Verifies [sigOldKey] against [oldSpkiDer] and [sigNewKey] against [newSpkiDer] over the
     * transcript. Any malformed key, signature or [cb] length yields false, never an exception.
     */
    fun verify(
        oldSpkiDer: ByteArray,
        newSpkiDer: ByteArray,
        cb: ByteArray,
        sigOldKey: ByteArray,
        sigNewKey: ByteArray,
    ): Boolean {
        val wellFormed =
            cb.size == ROTATION_CHALLENGE_LENGTH && isStrictP256Spki(oldSpkiDer) && isStrictP256Spki(newSpkiDer)
        if (!wellFormed) return false
        val transcript = transcript(oldSpkiDer, newSpkiDer, cb)
        val oldValid = verifyEcdsa(oldSpkiDer, transcript, sigOldKey)
        val newValid = verifyEcdsa(newSpkiDer, transcript, sigNewKey)
        return oldValid && newValid
    }

    /** The bytes both sides sign; exposed for signers and tests. */
    fun transcript(
        oldSpkiDer: ByteArray,
        newSpkiDer: ByteArray,
        cb: ByteArray,
    ): ByteArray =
        ROTATE_LABEL.toByteArray(Charsets.US_ASCII) + lengthPrefixed(oldSpkiDer) + lengthPrefixed(newSpkiDer) +
            lengthPrefixed(cb)
}

@Suppress("SwallowedException")
private fun verifyEcdsa(
    spkiDer: ByteArray,
    message: ByteArray,
    signatureDer: ByteArray,
): Boolean =
    try {
        val publicKey = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(spkiDer))
        Signature.getInstance("SHA256withECDSA").run {
            initVerify(publicKey)
            update(message)
            verify(signatureDer)
        }
    } catch (e: GeneralSecurityException) {
        false
    }
