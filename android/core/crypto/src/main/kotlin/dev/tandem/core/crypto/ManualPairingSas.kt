package dev.tandem.core.crypto

import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

private const val CHANNEL_BINDING_LENGTH = 32
private const val NONCE_LENGTH = 16
private const val SAS_MODULUS = 1_000_000L
private const val SAS_DIGITS = 6
private const val SAS_HMAC_PREFIX_BYTES = 8
private const val BYTE_MASK = 0xFFL
private const val BITS_PER_BYTE = 8
private const val PAIR_LABEL = "tandem-manual-pair-v1"
private const val COMMIT_LABEL = "tandem-manual-commit-v1"

/**
 * The three values a manual-pairing transcript binds to (ADR-008, SPEC.md "Manual pairing"): both
 * SPKIs observed on this TLS handshake and this session's channel-binding value (`cb`, the
 * `PairChallenge.challenge`). Never taken from a message body.
 */
class ManualPairingContext(
    val macSpkiDer: ByteArray,
    val phoneSpkiDer: ByteArray,
    val cb: ByteArray,
)

/**
 * Commit-then-reveal short authentication string for manual pairing (E73-03, ADR-008): both peers
 * derive the same commitments and SAS from their own observed SPKIs and `cb`. No fingerprint or
 * fingerprint prefix is ever an input here, or a substitute for the SAS.
 */
object ManualPairingSas {
    const val NONCE_BYTES = NONCE_LENGTH
    const val COMMITMENT_BYTES = 32

    /** Which peer a commitment belongs to; the role byte stops one side's commitment being reflected. */
    enum class Role(
        val byte: Byte,
    ) {
        PHONE(0x01),
        MAC(0x02),
    }

    /** `SHA-256(ASCII("tandem-manual-commit-v1") || roleByte || nonce || ctx)`. */
    fun commitment(
        role: Role,
        nonce: ByteArray,
        context: ManualPairingContext,
    ): ByteArray {
        require(nonce.size == NONCE_LENGTH) { "nonce must be $NONCE_LENGTH bytes" }
        return MessageDigest
            .getInstance("SHA-256")
            .digest(COMMIT_LABEL.toByteArray(Charsets.US_ASCII) + byteArrayOf(role.byte) + nonce + transcript(context))
    }

    /** True only if [commitment] equals the recomputed commitment for [nonce], compared in constant time. */
    fun verifyCommitment(
        commitment: ByteArray,
        role: Role,
        nonce: ByteArray,
        context: ManualPairingContext,
    ): Boolean {
        if (nonce.size != NONCE_LENGTH || commitment.size != COMMITMENT_BYTES) return false
        return constantTimeEquals(commitment, commitment(role, nonce, context))
    }

    /**
     * `u64be(first 8 bytes of HMAC-SHA256(nonceP || nonceM, ASCII("tandem-manual-pair-v1") || ctx)) mod
     * 1_000_000`, zero-padded to exactly 6 digits.
     */
    fun sas(
        noncePhone: ByteArray,
        nonceMac: ByteArray,
        context: ManualPairingContext,
    ): String {
        require(noncePhone.size == NONCE_LENGTH && nonceMac.size == NONCE_LENGTH) {
            "nonces must be $NONCE_LENGTH bytes"
        }
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(noncePhone + nonceMac, "HmacSHA256"))
        val digest = mac.doFinal(PAIR_LABEL.toByteArray(Charsets.US_ASCII) + transcript(context))
        var value = 0L
        for (i in 0 until SAS_HMAC_PREFIX_BYTES) {
            value = (value shl BITS_PER_BYTE) or (digest[i].toLong() and BYTE_MASK)
        }
        return java.lang.Long
            .remainderUnsigned(value, SAS_MODULUS)
            .toString()
            .padStart(SAS_DIGITS, '0')
    }

    /** `ctx = ASCII("tandem-manual-pair-v1") || LP(macSpkiDer) || LP(phoneSpkiDer) || LP(cb)`. */
    private fun transcript(context: ManualPairingContext): ByteArray {
        validateSpki(context.macSpkiDer)
        validateSpki(context.phoneSpkiDer)
        if (context.cb.size != CHANNEL_BINDING_LENGTH) throw PairingProofException.MalformedChannelBinding()
        return PAIR_LABEL.toByteArray(Charsets.US_ASCII) + lengthPrefixed(context.macSpkiDer) +
            lengthPrefixed(context.phoneSpkiDer) + lengthPrefixed(context.cb)
    }

    private fun validateSpki(spkiDer: ByteArray) {
        try {
            spkiFingerprint(spkiDer)
        } catch (cause: SpkiFingerprintException) {
            throw PairingProofException.MalformedSpki().initCause(cause)
        }
    }
}
