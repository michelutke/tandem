@file:Suppress("MagicNumber") // These literals are the colour tokens themselves (ui-spec.md §3.1).

package dev.tandem.core.designsystem

import androidx.compose.ui.graphics.Color
import kotlin.math.pow

// Colour tokens (ui-spec.md §3.1). Colour is a signal, never decoration: `signal` and `alert` are
// the only accents and must always be paired with text (ui-spec §1.5, §11).
object TandemColors {
    val ink = Color(0xFF0A0A0A)

    // Deviation: ui-spec.md §3.1 lists ink2 as #8A8A8A, but that colour is only ~3.45:1 against
    // `paper` (#FFFFFF) — short of the >= 4.5:1 acceptance criterion on E00-31 and its
    // `tandemColors_ink2OnPaper_contrastAtLeast4point5` tdd test. Darkened to #757575 (the
    // standard WCAG-AA-safe grey on white) so the token passes that acceptance criterion; flagged
    // for docs/design/ui-spec.md to reconcile.
    val ink2 = Color(0xFF757575)
    val line = Color(0x1A0A0A0A)
    val lineUnlitDot = Color(0x1F0A0A0A)
    val paper = Color(0xFFFFFFFF)
    val signal = Color(0xFF00D65A)
    val alert = Color(0xFFFF3B30)

    // Dark surfaces (scanner, ringing, mirror stream) invert ink/paper; signal/alert stay as-is
    // (ui-spec §3.1).
    val inkOnDark = paper
    val paperDark = ink

    /**
     * WCAG relative-contrast ratio between two colours, in `1:1`..`21:1`.
     * https://www.w3.org/TR/WCAG21/#contrast-minimum
     */
    fun contrastRatio(
        foreground: Color,
        background: Color,
    ): Double {
        val foregroundLuminance = relativeLuminance(foreground)
        val backgroundLuminance = relativeLuminance(background)
        val lighter = maxOf(foregroundLuminance, backgroundLuminance)
        val darker = minOf(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private fun relativeLuminance(color: Color): Double {
        fun linearize(channel: Float): Double {
            val c = channel.toDouble()
            return if (c <= 0.03928) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * linearize(color.red) + 0.7152 * linearize(color.green) + 0.0722 * linearize(color.blue)
    }
}
