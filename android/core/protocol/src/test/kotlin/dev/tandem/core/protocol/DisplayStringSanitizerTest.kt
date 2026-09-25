package dev.tandem.core.protocol

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.text.BreakIterator
import java.util.Locale
import kotlin.random.Random

/**
 * DisplayStringSanitizer tests (E14-21). Vectors come from the committed E01-24 manifest
 * `protocol/vectors/display-strings.json` (path wired via the `tandem.vectorsDir` system property,
 * android/core/protocol/build.gradle.kts), not a duplicated test resource — same loading approach
 * as [FrameEncoderTest] (E01-19)'s `FrameVectorTestSupport`.
 */
class DisplayStringSanitizerTest {
    @Test
    fun androidDisplaySanitizer_everyDisplayStringVector_matchesExpected() {
        val vectorsDir =
            System.getProperty("tandem.vectorsDir") ?: error("tandem.vectorsDir system property not set")
        val file = File(vectorsDir, "display-strings.json")
        val vectors =
            Json
                .parseToJsonElement(file.readText())
                .jsonObject
                .getValue("vectors")
                .jsonArray
        assertTrue(vectors.isNotEmpty(), "expected at least one display-strings vector")

        for (vector in vectors) {
            val obj = vector.jsonObject
            val id = obj.getValue("id").jsonPrimitive.content
            val input = obj.getValue("input").jsonObject
            val expected = obj.getValue("expected").jsonObject

            val raw = hexToBytes(input.getValue("rawUtf8Hex").jsonPrimitive.content)
            val kind = kindFor(input.getValue("kind").jsonPrimitive.content)

            val sanitized = DisplayStringSanitizer.sanitize(raw, kind)

            assertEquals(expected.getValue("sanitized").jsonPrimitive.content, sanitized, id)
        }
    }

    @Test
    fun androidDisplaySanitizer_randomNameInput_neverContainsBidiOrControlChars() {
        val random = Random(seed = 20250211)
        val boundary = BreakIterator.getCharacterInstance(Locale.ROOT)

        repeat(10_000) {
            val raw = ByteArray(random.nextInt(0, 256)) { random.nextInt(0, 256).toByte() }

            val sanitized = DisplayStringSanitizer.sanitize(raw, DisplayStringKind.NAME)

            sanitized.codePoints().forEach { codePoint ->
                assertFalse(isBidiControl(codePoint), "vector produced a bidi control: $codePoint from $raw")
                assertFalse(isC0OrC1(codePoint), "vector produced a C0/C1 control: $codePoint from $raw")
                assertFalse(isZeroWidth(codePoint), "vector produced a zero-width code point: $codePoint from $raw")
            }

            boundary.setText(sanitized)
            var graphemeCount = 0
            var start = boundary.first()
            var end = boundary.next()
            while (end != BreakIterator.DONE) {
                graphemeCount++
                start = end
                end = boundary.next()
            }
            assertTrue(
                graphemeCount <= DisplayStringKind.NAME.cap + 1,
                "sanitized name has $graphemeCount graphemes, more than the ${DisplayStringKind.NAME.cap} " +
                    "cap plus one possible ellipsis grapheme: $sanitized from $raw",
            )
        }
    }

    private fun kindFor(wireName: String): DisplayStringKind =
        when (wireName) {
            "name" -> DisplayStringKind.NAME
            "title" -> DisplayStringKind.TITLE
            "body" -> DisplayStringKind.BODY
            else -> error("unsupported display-string kind: $wireName")
        }

    private fun hexToBytes(hex: String): ByteArray =
        ByteArray(hex.length / 2) { i -> hex.substring(i * 2, i * 2 + 2).toInt(16).toByte() }

    private fun isBidiControl(codePoint: Int): Boolean =
        codePoint in
            setOf(0x200E, 0x200F, 0x061C, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069)

    private fun isC0OrC1(codePoint: Int): Boolean = (codePoint in 0x00..0x1F) || (codePoint in 0x7F..0x9F)

    private fun isZeroWidth(codePoint: Int): Boolean = codePoint in setOf(0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF)
}
