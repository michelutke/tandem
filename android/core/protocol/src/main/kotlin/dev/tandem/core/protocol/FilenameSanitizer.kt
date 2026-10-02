package dev.tandem.core.protocol

import java.text.Normalizer

private const val MAX_FILENAME_BYTES = 255
private const val TRANSFER_ID_PREFIX_LENGTH = 8
private const val MAX_DEVICE_NUMBER = 9
private val WINDOWS_RESERVED_STEMS: Set<String> =
    setOf("CON", "PRN", "AUX", "NUL") + (1..MAX_DEVICE_NUMBER).flatMap { listOf("COM$it", "LPT$it") }

/** Receiver-side `FileOffer.name` sanitizer (docs/protocol/SPEC.md #filename-sanitization, E40-02). */
object FilenameSanitizer {
    /** Returns the safe destination filename, or null when the offer must be rejected with `INVALID_NAME`. */
    fun sanitize(
        name: String,
        transferId: String,
    ): String? = if (name.contains('\u0000')) null else sanitizeValidName(name, transferId)

    private fun sanitizeValidName(
        name: String,
        transferId: String,
    ): String {
        val lastComponent = name.split('/', '\\').last()
        val text =
            Normalizer
                .normalize(lastComponent, Normalizer.Form.NFC)
                .filterNot { it in '\u202A'..'\u202E' || it in '\u2066'..'\u2069' }
                .map { if (it < ' ' || it == '\u007F' || it == ':') '_' else it }
                .joinToString("")
                .trimStart('.')
        val reserved = text.substringBefore('.').uppercase() in WINDOWS_RESERVED_STEMS
        return when {
            text.isEmpty() -> "file-${transferId.take(TRANSFER_ID_PREFIX_LENGTH)}"
            reserved -> truncateToFilenameLimit("_$text")
            else -> truncateToFilenameLimit(text)
        }
    }

    private fun truncateToFilenameLimit(name: String): String {
        if (name.toByteArray(Charsets.UTF_8).size <= MAX_FILENAME_BYTES) return name

        val dot = name.lastIndexOf('.')
        var stem = if (dot > 0) name.substring(0, dot) else name
        var extension = if (dot > 0) name.substring(dot) else ""
        var budget = MAX_FILENAME_BYTES - extension.toByteArray(Charsets.UTF_8).size
        if (budget < 1) {
            stem = name
            extension = ""
            budget = MAX_FILENAME_BYTES
        }

        val kept = StringBuilder()
        var used = 0
        for (codePoint in stem.codePoints().toArray()) {
            val character = String(Character.toChars(codePoint))
            val size = character.toByteArray(Charsets.UTF_8).size
            if (used + size > budget) break
            kept.append(character)
            used += size
        }
        return kept.toString() + extension
    }
}
