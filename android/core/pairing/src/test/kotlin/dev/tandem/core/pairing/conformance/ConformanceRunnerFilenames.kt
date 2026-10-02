package dev.tandem.core.pairing.conformance

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.text.Normalizer

private const val MAX_FILENAME_BYTES = 255
private const val INVALID_NAME_ERROR = "invalidName"
private val WINDOWS_RESERVED_STEMS: Set<String> =
    setOf("CON", "PRN", "AUX", "NUL") + (1..9).flatMap { listOf("COM$it", "LPT$it") }

/** `filenames` category (E40-02): applies the reference implementation of
 * docs/protocol/SPEC.md #filename-sanitization below to each vector's raw name. */
internal fun filenamesOutcome(vector: JsonObject): VectorOutcome {
    val id = vector.getValue("id").jsonPrimitive.content
    val input = vector.getValue("input").jsonObject
    val name = String(hexToBytes(input.getValue("rawUtf8Hex").jsonPrimitive.content), Charsets.UTF_8)
    val transferId = input.getValue("transferId").jsonPrimitive.content
    val expected =
        vector["expectedError"]?.jsonPrimitive?.content
            ?: vector
                .getValue("expected")
                .jsonObject
                .getValue("filename")
                .jsonPrimitive.content
    val actual = sanitizeFilename(name, transferId) ?: INVALID_NAME_ERROR
    return VectorOutcome(id, "filenames", if (actual == expected) "pass" else "fail", expected, actual)
}

private fun sanitizeFilename(
    name: String,
    transferId: String,
): String? = if (name.contains('\u0000')) null else sanitizeValidFilename(name, transferId)

private fun sanitizeValidFilename(
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
        text.isEmpty() -> "file-${transferId.take(8)}"
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
