package dev.tandem.core.crypto

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** SPEC.md #1, Channel binding: `cb` is exactly the 32 bytes of the `PairChallenge` sent on this connection. */
private const val CHANNEL_BINDING_LENGTH = 32

/** A `PairingProof.compute`/`verify` output is always a raw HMAC-SHA256 digest. */
private const val PROOF_LENGTH = 32

private const val PROOF_LABEL = "tandem-pair-v1"
private const val CODE_LABEL = "tandem-pair-code-v1"

/** SPEC.md #2, Confirmation code: `mod 1000000`, zero-padded to exactly 6 digits. */
private const val CONFIRMATION_CODE_MODULUS = 1_000_000
private const val CONFIRMATION_CODE_DIGITS = 6

private const val BYTE_MASK = 0xFF
private const val BITS_PER_BYTE = 8

/** `LP(x)`'s u16be length prefix can represent at most this many bytes (SPEC.md #2). */
private const val MAX_LENGTH_PREFIXED_SIZE = 0xFFFF

/**
 * SPEC.md #2's precondition for both `PairingProof` and `ConfirmationCode`: a non-conforming
 * `macSpkiDer`/`phoneSpkiDer`, `cb`, or (`verify` only) candidate proof is rejected before any
 * HMAC is ever computed (invariant 6).
 */
sealed class PairingProofException(
    message: String,
) : Exception(message) {
    /** `macSpkiDer`/`phoneSpkiDer` is not a 91-byte uncompressed P-256 SubjectPublicKeyInfo DER. */
    class MalformedSpki : PairingProofException("SPKI is not a 91-byte uncompressed P-256 SubjectPublicKeyInfo DER")

    /** `cb` is not exactly the 32-byte `PairChallenge` value (SPEC.md #1, Channel binding). */
    class MalformedChannelBinding : PairingProofException("cb must be exactly $CHANNEL_BINDING_LENGTH bytes")

    /** A candidate proof passed to `PairingProof.verify` is not exactly 32 bytes. */
    class MalformedProof : PairingProofException("proof must be exactly $PROOF_LENGTH bytes")
}

/**
 * SPEC.md #2 "Proof computation": `proof = HMAC-SHA256(secret, ASCII("tandem-pair-v1") ||
 * LP(macSpkiDer) || LP(phoneSpkiDer) || LP(cb))`, where `secret` is the 16-byte pairing secret
 * from the QR `s` field and `cb` is this session's channel-binding value. Consumed by E14-06.
 */
object PairingProof {
    /** Computes the raw 32-byte proof. Throws [PairingProofException] before any HMAC runs. */
    fun compute(
        secret: ByteArray,
        macSpkiDer: ByteArray,
        phoneSpkiDer: ByteArray,
        cb: ByteArray,
    ): ByteArray = hmacSha256(secret, transcript(PROOF_LABEL, macSpkiDer, phoneSpkiDer, cb))

    /**
     * Recomputes `proof` from the verifier's own [secret]/[macSpkiDer]/[phoneSpkiDer]/[cb] and
     * compares it against [proof] in constant time (SPEC.md #2, invariant 6). A [proof] that is
     * not exactly 32 bytes is rejected as [PairingProofException.MalformedProof] before any HMAC
     * or compare runs.
     */
    fun verify(
        proof: ByteArray,
        secret: ByteArray,
        macSpkiDer: ByteArray,
        phoneSpkiDer: ByteArray,
        cb: ByteArray,
    ): Boolean {
        if (proof.size != PROOF_LENGTH) throw PairingProofException.MalformedProof()
        val expected = compute(secret, macSpkiDer, phoneSpkiDer, cb)
        return constantTimeEquals(proof, expected)
    }
}

/**
 * SPEC.md #2 "Confirmation code": the 6-digit code shown on both the Mac dialog and the phone,
 * derived from the same `secret`/`macSpkiDer`/`phoneSpkiDer`/`cb` as [PairingProof] but under a
 * distinct label so the two HMAC outputs never collide.
 */
object ConfirmationCode {
    /** Computes the zero-padded, exactly-6-digit confirmation code string (e.g. `"007042"`). */
    fun compute(
        secret: ByteArray,
        macSpkiDer: ByteArray,
        phoneSpkiDer: ByteArray,
        cb: ByteArray,
    ): String {
        val digest = hmacSha256(secret, transcript(CODE_LABEL, macSpkiDer, phoneSpkiDer, cb))
        var value = 0L
        for (i in 0 until Int.SIZE_BYTES) {
            value = (value shl BITS_PER_BYTE) or (digest[i].toLong() and BYTE_MASK.toLong())
        }
        return (value % CONFIRMATION_CODE_MODULUS).toString().padStart(CONFIRMATION_CODE_DIGITS, '0')
    }
}

private fun transcript(
    label: String,
    macSpkiDer: ByteArray,
    phoneSpkiDer: ByteArray,
    cb: ByteArray,
): ByteArray {
    validateSpki(macSpkiDer)
    validateSpki(phoneSpkiDer)
    if (cb.size != CHANNEL_BINDING_LENGTH) throw PairingProofException.MalformedChannelBinding()

    return label.toByteArray(Charsets.US_ASCII) + lengthPrefixed(macSpkiDer) + lengthPrefixed(phoneSpkiDer) +
        lengthPrefixed(cb)
}

private fun validateSpki(spkiDer: ByteArray) {
    try {
        spkiFingerprint(spkiDer)
    } catch (cause: SpkiFingerprintException) {
        throw PairingProofException.MalformedSpki().initCause(cause)
    }
}

/** `LP(x) = u16be(len(x)) || x` (SPEC.md #2, Proof computation). */
private fun lengthPrefixed(x: ByteArray): ByteArray {
    require(x.size <= MAX_LENGTH_PREFIXED_SIZE) { "length-prefixed value exceeds u16be range" }
    return byteArrayOf((x.size ushr BITS_PER_BYTE).toByte(), x.size.toByte()) + x
}

private fun hmacSha256(
    secret: ByteArray,
    transcript: ByteArray,
): ByteArray {
    val mac = Mac.getInstance("HmacSHA256")
    mac.init(SecretKeySpec(secret, "HmacSHA256"))
    return mac.doFinal(transcript)
}
