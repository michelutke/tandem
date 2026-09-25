package dev.tandem.core.pairing.qr

import java.io.ByteArrayOutputStream
import java.util.Base64

/**
 * base64url (no padding) and percent-decoding helpers for [QrPayloadParser]'s `fp`/`s`/`n` fields
 * (SPEC.md §2). Hand-rolled rather than `android.net.Uri`, so this module is pure JVM / testable
 * off-device.
 */
internal object QrEncoding {
    private const val BASE64_BLOCK_SIZE = 4
    private const val PERCENT_ESCAPE_LENGTH = 3
    private const val HEX_RADIX = 16
    private const val BYTE_MASK = 0xFF
    private val BASE64URL_ALPHABET = (('A'..'Z') + ('a'..'z') + ('0'..'9') + listOf('-', '_')).toSet()

    /** base64url, no padding: rejects any char outside the alphabet before padding and decoding. */
    fun decodeBase64Url(value: String): ByteArray? {
        if (value.isEmpty() || value.any { it !in BASE64URL_ALPHABET }) return null
        val padding = (BASE64_BLOCK_SIZE - value.length % BASE64_BLOCK_SIZE) % BASE64_BLOCK_SIZE
        return try {
            Base64.getUrlDecoder().decode(value + "=".repeat(padding))
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    /** Percent-decodes [raw] to raw bytes; an invalid `%XX` escape is kept as a literal `%` byte. */
    fun percentDecode(raw: String): ByteArray {
        val out = ByteArrayOutputStream(raw.length)
        var index = 0
        while (index < raw.length) {
            val char = raw[index]
            if (isPercentEscape(raw, index)) {
                out.write(raw.substring(index + 1, index + PERCENT_ESCAPE_LENGTH).toInt(radix = HEX_RADIX))
                index += PERCENT_ESCAPE_LENGTH
            } else {
                out.write(char.code and BYTE_MASK)
                index += 1
            }
        }
        return out.toByteArray()
    }

    private fun isPercentEscape(
        raw: String,
        index: Int,
    ): Boolean =
        raw[index] == '%' &&
            index + 2 < raw.length &&
            isHexDigit(raw[index + 1]) &&
            isHexDigit(raw[index + 2])

    private fun isHexDigit(char: Char): Boolean = char in '0'..'9' || char in 'a'..'f' || char in 'A'..'F'
}
