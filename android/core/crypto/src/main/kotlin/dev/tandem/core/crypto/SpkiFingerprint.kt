package dev.tandem.core.crypto

import java.security.MessageDigest
import java.util.Base64

/** Length of an uncompressed P-256 SubjectPublicKeyInfo DER (SPEC.md §1, Certificate handling). */
private const val SPKI_DER_LENGTH = 91

/** SHA-256 digest length in bytes. */
private const val FINGERPRINT_LENGTH = 32

/** SEC1 point length for an uncompressed P-256 point: 1-byte `0x04` prefix + 32-byte X + 32-byte Y. */
private const val UNCOMPRESSED_POINT_LENGTH = 65

private const val OID_EC_PUBLIC_KEY = "1.2.840.10045.2.1"
private const val OID_PRIME256V1 = "1.2.840.10045.3.1.7"

private const val BYTE_MASK = 0xFF
private const val TAG_SEQUENCE = 0x30
private const val TAG_OID = 0x06
private const val TAG_BIT_STRING = 0x03
private const val POINT_PREFIX_UNCOMPRESSED: Byte = 0x04
private const val POINT_PREFIX_COMPRESSED_EVEN: Byte = 0x02
private const val POINT_PREFIX_COMPRESSED_ODD: Byte = 0x03
private const val LENGTH_LONG_FORM_FLAG = 0x80
private const val LENGTH_BYTES_MASK = 0x7F
private const val MAX_LENGTH_BYTES = 4
private const val BITS_PER_BYTE = 8
private const val OID_ARC_DIVISOR = 40
private const val OID_CONTINUATION_BIT = 0x80
private const val OID_VALUE_MASK = 0x7F
private const val OID_VALUE_SHIFT = 7

/**
 * SHA-256 fingerprint of a peer's `SubjectPublicKeyInfo` (E01-17; SPEC.md §1 "Verify-callback
 * algorithm", steps 2-3). [bytes] is the raw 32-byte digest, for constant-time comparisons
 * ([constantTimeEquals]) only — never compare fingerprints with `==`/`.equals()`. [base64Url] is
 * the same value carried by the QR `fp` param (SPEC.md §2, F-2.1): 43 characters, unpadded.
 */
class SpkiFingerprint(
    val bytes: ByteArray,
) {
    init {
        require(bytes.size == FINGERPRINT_LENGTH) { "fingerprint must be $FINGERPRINT_LENGTH bytes" }
    }

    val base64Url: String by lazy { Base64.getUrlEncoder().withoutPadding().encodeToString(bytes) }
}

/**
 * SPEC.md §1's precondition for the leaf-key check (`#handshake-and-tls-profile`, "Certificate
 * handling and the leaf-only check"): a non-conforming SPKI is rejected before any fingerprint is
 * ever computed. The three cases mirror `tools/vectors/spki_fingerprint.py`'s negative vectors.
 */
sealed class SpkiFingerprintException(
    message: String,
) : Exception(message) {
    /** A compressed SEC1 point (`0x02`/`0x03` prefix) instead of the required uncompressed `0x04`. */
    class UnsupportedPointEncoding : SpkiFingerprintException("SPKI point is not an uncompressed P-256 point")

    /** A key type or curve other than P-256 (e.g. RSA, or an EC key on a different curve). */
    class UnsupportedKeyType : SpkiFingerprintException("SPKI is not an uncompressed P-256 key")

    /** DER that is truncated, has unexpected tags, or otherwise fails to parse as a SPKI. */
    class MalformedSpki : SpkiFingerprintException("SPKI DER is malformed")
}

private fun malformed(): Nothing = throw SpkiFingerprintException.MalformedSpki()

private fun unsupportedKeyType(): Nothing = throw SpkiFingerprintException.UnsupportedKeyType()

private fun unsupportedPointEncoding(): Nothing = throw SpkiFingerprintException.UnsupportedPointEncoding()

/**
 * Computes the SHA-256 fingerprint of [spkiDer], the peer leaf certificate's DER-encoded
 * `SubjectPublicKeyInfo`. Validates first that it is an uncompressed P-256 SPKI, exactly 91 bytes
 * of DER (SPEC.md §1, Certificate handling and the leaf-only check) — a non-conforming key throws
 * [SpkiFingerprintException] before any digest is computed, matching the verify-callback
 * algorithm's ordering (SPEC.md §1: leaf-key check is step 2, fingerprint compute is step 3).
 */
fun spkiFingerprint(spkiDer: ByteArray): SpkiFingerprint {
    validateP256UncompressedSpki(spkiDer)
    return SpkiFingerprint(MessageDigest.getInstance("SHA-256").digest(spkiDer))
}

private fun validateP256UncompressedSpki(der: ByteArray) {
    val reader = DerReader(der)

    reader.readTag(TAG_SEQUENCE)
    val outerLength = reader.readLength()
    if (reader.remaining() != outerLength) malformed()

    reader.readTag(TAG_SEQUENCE) // AlgorithmIdentifier
    reader.readLength()

    reader.readTag(TAG_OID) // algorithm OID
    val algorithmOid = decodeOid(reader.readBytes(reader.readLength()))
    if (algorithmOid != OID_EC_PUBLIC_KEY) unsupportedKeyType()

    reader.readTag(TAG_OID) // curve OID
    val curveOid = decodeOid(reader.readBytes(reader.readLength()))
    if (curveOid != OID_PRIME256V1) unsupportedKeyType()

    reader.readTag(TAG_BIT_STRING) // subjectPublicKey
    val bitString = reader.readBytes(reader.readLength())
    if (bitString.isEmpty() || bitString[0] != 0.toByte()) malformed()
    val point = bitString.copyOfRange(1, bitString.size)

    when (point.firstOrNull()) {
        POINT_PREFIX_UNCOMPRESSED -> Unit
        POINT_PREFIX_COMPRESSED_EVEN, POINT_PREFIX_COMPRESSED_ODD -> unsupportedPointEncoding()
        else -> malformed()
    }
    if (point.size != UNCOMPRESSED_POINT_LENGTH) malformed()

    if (reader.remaining() != 0 || der.size != SPKI_DER_LENGTH) malformed()
}

private fun decodeOid(bytes: ByteArray): String {
    if (bytes.isEmpty()) malformed()
    val first = bytes[0].toInt() and BYTE_MASK
    val components = mutableListOf(first / OID_ARC_DIVISOR, first % OID_ARC_DIVISOR)

    var value = 0L
    for (i in 1 until bytes.size) {
        val byte = bytes[i].toInt() and BYTE_MASK
        value = (value shl OID_VALUE_SHIFT) or (byte and OID_VALUE_MASK).toLong()
        if (byte and OID_CONTINUATION_BIT == 0) {
            components += value.toInt()
            value = 0
        }
    }
    if (value != 0L) malformed() // truncated base-128 component
    return components.joinToString(".")
}

/** Minimal, bounds-checked DER TLV reader; any structural problem throws [SpkiFingerprintException.MalformedSpki]. */
private class DerReader(
    private val data: ByteArray,
) {
    private var position = 0

    fun remaining(): Int = data.size - position

    fun readTag(expected: Int): Int {
        if (position >= data.size) malformed()
        val tag = data[position].toInt() and BYTE_MASK
        if (tag != expected) malformed()
        position++
        return tag
    }

    fun readLength(): Int {
        if (position >= data.size) malformed()
        var length = data[position].toInt() and BYTE_MASK
        position++
        if (length and LENGTH_LONG_FORM_FLAG != 0) {
            val lengthBytes = length and LENGTH_BYTES_MASK
            if (lengthBytes == 0 || lengthBytes > MAX_LENGTH_BYTES || position + lengthBytes > data.size) {
                malformed()
            }
            length = 0
            repeat(lengthBytes) {
                length = (length shl BITS_PER_BYTE) or (data[position].toInt() and BYTE_MASK)
                position++
            }
        }
        if (length < 0 || position + length > data.size) malformed()
        return length
    }

    fun readBytes(length: Int): ByteArray {
        if (position + length > data.size) malformed()
        val result = data.copyOfRange(position, position + length)
        position += length
        return result
    }
}
