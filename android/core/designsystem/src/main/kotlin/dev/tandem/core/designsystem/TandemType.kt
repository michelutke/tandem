package dev.tandem.core.designsystem

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// Type families (ui-spec.md §3.2): Inter Tight for UI text, JetBrains Mono for numbers that are
// codes (pairing code, fingerprints, file sizes, row numbers).
//
// Deviation: no font-asset issue exists yet for E00-31 and no .ttf/.otf files are bundled in this
// repo, so these fall back to the platform sans-serif / monospace families. Swapping in the real
// font resources (as `FontFamily(Font(R.font....))`) is a drop-in change that does not touch any
// call site, since every component reads type through `TandemType`.
val InterTightFontFamily: FontFamily = FontFamily.SansSerif
val JetBrainsMonoFontFamily: FontFamily = FontFamily.Monospace

/** Type scale (ui-spec.md §3.2). Screens must use these roles instead of literal `TextStyle`s. */
object TandemType {
    /** Ring centre, timers. 64–96sp in the spec; components may override `fontSize` to fit. */
    val displayNumeral =
        TextStyle(
            fontFamily = InterTightFontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 80.sp,
            letterSpacing = (-3).sp,
        )

    /** Pairing code, key fingerprints: a display numeral that is a code, so it is set in mono. */
    val displayNumeralCode = displayNumeral.copy(fontFamily = JetBrainsMonoFontFamily)

    /** Title pair, line 1 ("Pixel 9."): bold, same size as [titleState]. */
    val titleEmphasis =
        TextStyle(
            fontFamily = InterTightFontFamily,
            fontWeight = FontWeight.Bold,
            fontSize = 30.sp,
            letterSpacing = (-1).sp,
        )

    /** Title pair, line 2 ("Connected."): regular weight, grey (or red for trust failure). */
    val titleState =
        TextStyle(
            fontFamily = InterTightFontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 30.sp,
            letterSpacing = (-1).sp,
        )

    val rowTitle =
        TextStyle(
            fontFamily = InterTightFontFamily,
            fontWeight = FontWeight.SemiBold,
            fontSize = 16.sp,
            letterSpacing = (-0.3).sp,
        )

    val body =
        TextStyle(
            fontFamily = InterTightFontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 14.sp,
            lineHeight = 20.sp,
        )

    /** Units, timestamps. */
    val meta =
        TextStyle(
            fontFamily = InterTightFontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 12.sp,
        )

    /** Row numbers ("01 02 03"), file sizes, short codes at meta size: always mono. */
    val metaMono =
        TextStyle(
            fontFamily = JetBrainsMonoFontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 12.sp,
        )
}
