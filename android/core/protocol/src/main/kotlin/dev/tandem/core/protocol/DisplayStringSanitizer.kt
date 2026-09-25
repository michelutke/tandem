package dev.tandem.core.protocol

import java.text.BreakIterator
import java.text.Normalizer
import java.util.Locale

/**
 * A surface's length-cap category (SPEC.md #untrusted-peer-strings-display-sanitization, E01-23):
 * `NAME` and `TITLE` are single-line, `BODY` is multi-line (its U+000A line feeds survive
 * sanitization; every other surface's do not). Caps count Unicode scalar values, not UTF-8/UTF-16
 * code units.
 */
enum class DisplayStringKind(
    val cap: Int,
    val multiLine: Boolean,
) {
    NAME(cap = 64, multiLine = false),
    TITLE(cap = 256, multiLine = false),
    BODY(cap = 4096, multiLine = true),
}

/**
 * Sanitizes a peer-supplied, untrusted display string before it is ever rendered, per SPEC.md
 * #untrusted-peer-strings-display-sanitization (E01-23)'s seven-step order: UTF-8 decode with
 * U+FFFD substitution, NFC, strip bidi controls, strip C0/C1 controls (except a `body`'s line
 * feeds), single-line fields additionally strip zero-width code points and collapse whitespace
 * runs, re-NFC, then grapheme-safe truncation to the [DisplayStringKind]'s cap with an appended
 * ellipsis if truncated. Validated against the E01-24 vectors (`protocol/vectors/display-strings.json`),
 * this rule's cross-platform tie-breaker; mirrors `tools/vectors/display_strings.py` exactly.
 *
 * No trust decision anywhere in the protocol is ever based on a sanitized string: this exists only
 * to make a hostile peer-supplied string safe to render, never to authenticate it.
 */
object DisplayStringSanitizer {
    // Bidirectional-control code points (SPEC.md step 3): LEFT-TO-RIGHT/RIGHT-TO-LEFT MARK, ARABIC
    // LETTER MARK, the LEFT-TO-RIGHT/RIGHT-TO-LEFT EMBEDDING/OVERRIDE pair, POP DIRECTIONAL
    // FORMATTING, the LEFT-TO-RIGHT/RIGHT-TO-LEFT/FIRST-STRONG ISOLATE trio, and POP DIRECTIONAL
    // ISOLATE.
    private const val LEFT_TO_RIGHT_MARK = 0x200E
    private const val RIGHT_TO_LEFT_MARK = 0x200F
    private const val ARABIC_LETTER_MARK = 0x061C
    private const val LEFT_TO_RIGHT_EMBEDDING = 0x202A
    private const val RIGHT_TO_LEFT_EMBEDDING = 0x202B
    private const val POP_DIRECTIONAL_FORMATTING = 0x202C
    private const val LEFT_TO_RIGHT_OVERRIDE = 0x202D
    private const val RIGHT_TO_LEFT_OVERRIDE = 0x202E
    private const val LEFT_TO_RIGHT_ISOLATE = 0x2066
    private const val RIGHT_TO_LEFT_ISOLATE = 0x2067
    private const val FIRST_STRONG_ISOLATE = 0x2068
    private const val POP_DIRECTIONAL_ISOLATE = 0x2069
    private val BIDI_CONTROLS =
        setOf(
            LEFT_TO_RIGHT_MARK,
            RIGHT_TO_LEFT_MARK,
            ARABIC_LETTER_MARK,
            LEFT_TO_RIGHT_EMBEDDING,
            RIGHT_TO_LEFT_EMBEDDING,
            POP_DIRECTIONAL_FORMATTING,
            LEFT_TO_RIGHT_OVERRIDE,
            RIGHT_TO_LEFT_OVERRIDE,
            LEFT_TO_RIGHT_ISOLATE,
            RIGHT_TO_LEFT_ISOLATE,
            FIRST_STRONG_ISOLATE,
            POP_DIRECTIONAL_ISOLATE,
        )

    // Zero-width code points (SPEC.md step 5): ZERO WIDTH SPACE/NON-JOINER/JOINER, WORD JOINER, and
    // ZERO WIDTH NO-BREAK SPACE (byte-order mark).
    private const val ZERO_WIDTH_SPACE = 0x200B
    private const val ZERO_WIDTH_NON_JOINER = 0x200C
    private const val ZERO_WIDTH_JOINER = 0x200D
    private const val WORD_JOINER = 0x2060
    private const val ZERO_WIDTH_NO_BREAK_SPACE = 0xFEFF
    private val ZERO_WIDTH =
        setOf(ZERO_WIDTH_SPACE, ZERO_WIDTH_NON_JOINER, ZERO_WIDTH_JOINER, WORD_JOINER, ZERO_WIDTH_NO_BREAK_SPACE)

    private const val ELLIPSIS = '…'
    private const val LINE_FEED = 0x0A
    private const val C0_START = 0x00
    private const val C0_END = 0x1F
    private const val C1_START = 0x7F
    private const val C1_END = 0x9F
    private val WHITESPACE_RUN = Regex("(?U)\\s+")

    fun sanitize(
        raw: ByteArray,
        kind: DisplayStringKind,
    ): String {
        var text = String(raw, Charsets.UTF_8)
        text = Normalizer.normalize(text, Normalizer.Form.NFC)
        text = filterCodePoints(text) { codePoint -> codePoint !in BIDI_CONTROLS }

        val keepLineFeed = kind.multiLine
        text = filterCodePoints(text) { codePoint -> !isC0OrC1(codePoint) || (keepLineFeed && codePoint == LINE_FEED) }

        if (!kind.multiLine) {
            text = filterCodePoints(text) { codePoint -> codePoint !in ZERO_WIDTH }
            text = WHITESPACE_RUN.replace(text, " ")
        }

        text = Normalizer.normalize(text, Normalizer.Form.NFC)

        return truncateGraphemeSafe(text, kind.cap)
    }

    private fun isC0OrC1(codePoint: Int): Boolean = (codePoint in C0_START..C0_END) || (codePoint in C1_START..C1_END)

    private inline fun filterCodePoints(
        text: String,
        keep: (Int) -> Boolean,
    ): String {
        val builder = StringBuilder(text.length)
        var index = 0
        while (index < text.length) {
            val codePoint = text.codePointAt(index)
            if (keep(codePoint)) builder.appendCodePoint(codePoint)
            index += Character.charCount(codePoint)
        }
        return builder.toString()
    }

    private fun truncateGraphemeSafe(
        text: String,
        cap: Int,
    ): String {
        if (text.codePointCount(0, text.length) <= cap) return text

        val boundary = BreakIterator.getCharacterInstance(Locale.ROOT)
        boundary.setText(text)

        var clusterStart = boundary.first()
        var clusterEnd = boundary.next()
        var kept = 0
        var cutIndex = 0
        while (clusterEnd != BreakIterator.DONE) {
            val clusterScalars = text.codePointCount(clusterStart, clusterEnd)
            if (kept + clusterScalars > cap) break
            kept += clusterScalars
            cutIndex = clusterEnd
            clusterStart = clusterEnd
            clusterEnd = boundary.next()
        }

        return text.substring(0, cutIndex) + ELLIPSIS
    }
}
