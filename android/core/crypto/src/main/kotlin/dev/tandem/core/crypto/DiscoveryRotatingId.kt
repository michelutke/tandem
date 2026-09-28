package dev.tandem.core.crypto

import java.nio.ByteBuffer
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** One UTC calendar day, in seconds (SPEC.md "Discovery TXT record"). */
private const val SECONDS_PER_DAY = 86_400L

/** `DiscoveryRotatingId.compute`'s output is always truncated to this many bytes. */
private const val ID_BYTE_COUNT = 8

/**
 * The Bonjour instance-name rotating id (E21-02/E21-05, SPEC.md "Discovery TXT record"): a value
 * that changes once per UTC calendar day so the advertised `_tandem._tcp` service name never sits
 * still on the local network, without either peer needing to exchange anything beyond the
 * already-pinned mac SPKI fingerprint.
 *
 * `dayIndex = floor(unixSecondsUtc / 86400)`, computed from UTC seconds only -- never a local
 * `Calendar`/`TimeZone`, since a device in any local time zone must derive the same day boundary.
 * `id = first 8 bytes of HMAC-SHA256(key: macSpkiFingerprint, message: dayIndex as signed 64-bit
 * big-endian)`. A receiver that has this Mac's paired SPKI fingerprint recomputes the id for
 * `dayIndex-1`/`dayIndex`/`dayIndex+1` (a +/-1 day clock-skew window) and recognizes the advertised
 * id only if it matches one of those three candidates byte-for-byte as a case-sensitive string --
 * [recognize] never decodes back to bytes before comparing, so an uppercase-hex re-encoding of an
 * otherwise-correct id is not recognized.
 */
object DiscoveryRotatingId {
    /** Thrown by [recognize] on a non-match (invariant 3: a match/non-match is never a trust decision). */
    sealed class RecognitionException(
        message: String,
    ) : Exception(message) {
        /** `advertisedIdHex` did not case-sensitively match any of `candidateHexIds`. */
        class NotRecognized : RecognitionException("advertised id did not match any candidate id")
    }

    /**
     * Floors `unixSecondsUtc / 86400` correctly for negative inputs too (a receiver computes
     * `dayIndex - 1`, which can go negative near the Unix epoch) via [Math.floorDiv].
     */
    fun dayIndex(unixSecondsUtc: Long): Long = Math.floorDiv(unixSecondsUtc, SECONDS_PER_DAY)

    /**
     * HMAC-SHA256(key: [macSpkiFingerprint], message: [dayIndex] as signed 64-bit big-endian),
     * truncated to its first 8 bytes. Big-endian, fixed-width encoding keeps the message bytes
     * identical across platforms regardless of native byte order.
     */
    fun compute(
        macSpkiFingerprint: ByteArray,
        dayIndex: Long,
    ): ByteArray {
        val message = ByteBuffer.allocate(Long.SIZE_BYTES).putLong(dayIndex).array()
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(macSpkiFingerprint, "HmacSHA256"))
        val digest = mac.doFinal(message)
        return digest.copyOf(ID_BYTE_COUNT)
    }

    /** [compute]'s bytes, lowercase hex -- the wire form advertised in the TXT record's `id` field. */
    fun computeHex(
        macSpkiFingerprint: ByteArray,
        dayIndex: Long,
    ): String = compute(macSpkiFingerprint, dayIndex).joinToString("") { "%02x".format(it) }

    /**
     * The three ids a receiver must accept for [receiverUnixSecondsUtc]'s day, in
     * `[dayIndex - 1, dayIndex, dayIndex + 1]` order.
     */
    fun candidateHexIds(
        macSpkiFingerprint: ByteArray,
        receiverUnixSecondsUtc: Long,
    ): List<String> {
        val today = dayIndex(receiverUnixSecondsUtc)
        return listOf(today - 1, today, today + 1).map { computeHex(macSpkiFingerprint, it) }
    }

    /**
     * Throws [RecognitionException.NotRecognized] unless [advertisedIdHex] is byte-for-byte (i.e.
     * case-sensitive string) equal to one of [candidateHexIds] -- never canonicalized/lowercased
     * first.
     */
    fun recognize(
        advertisedIdHex: String,
        candidateHexIds: List<String>,
    ) {
        if (advertisedIdHex !in candidateHexIds) {
            throw RecognitionException.NotRecognized()
        }
    }
}
