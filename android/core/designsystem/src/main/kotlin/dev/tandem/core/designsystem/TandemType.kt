package dev.tandem.core.designsystem

import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// Type families (ui-spec.md §3.2): Inter Tight (variable `wght`) for UI text, JetBrains Mono for
// numbers that are codes (pairing code, fingerprints, file sizes, row numbers). Both are bundled
// under SIL OFL 1.1 (core/designsystem/licenses).
@OptIn(ExperimentalTextApi::class)
val InterTightFontFamily: FontFamily =
    FontFamily(
        listOf(FontWeight.Normal, FontWeight.SemiBold, FontWeight.Bold).map { weight ->
            Font(
                resId = R.font.inter_tight,
                weight = weight,
                variationSettings = FontVariation.Settings(FontVariation.weight(weight.weight)),
            )
        },
    )
val JetBrainsMonoFontFamily: FontFamily = FontFamily(Font(R.font.jetbrains_mono_regular))

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
