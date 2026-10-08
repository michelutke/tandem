@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.drawRingDots
import dev.tandem.core.designsystem.rememberCrossfadeTransition
import dev.tandem.core.designsystem.tandemAnimateFloatAsState
import kotlin.math.roundToInt

/**
 * The home ring (ui-spec.md §5.2, §6): a big numeral with dots lit clockwise for progress
 * (motion #01). Exposes a single TalkBack content description carrying the numeric value, since
 * the dots themselves are decorative once the numeral is present (ui-spec §11).
 */
@Composable
@Suppress("LongParameterList") // slot-style component with several independent optional knobs
fun DotRing(
    value: Int,
    maxValue: Int,
    unit: String,
    modifier: Modifier = Modifier,
    dotCount: Int = 24,
    diameter: Dp = 200.dp,
) {
    val fraction = if (maxValue > 0) (value.toFloat() / maxValue.toFloat()).coerceIn(0f, 1f) else 0f
    val animatedFraction by tandemAnimateFloatAsState(targetValue = fraction)
    val litDots = (animatedFraction * dotCount).roundToInt()

    Box(
        modifier =
            modifier
                .size(diameter)
                .clearAndSetSemantics { contentDescription = "$value$unit" },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            drawRingDots(dotCount = dotCount, litDots = litDots)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(text = value.toString(), style = TandemType.displayNumeral, color = TandemColors.ink)
            val crossfade = rememberCrossfadeTransition()
            AnimatedContent(targetState = unit, transitionSpec = { crossfade }, label = "DotRingUnit") { label ->
                Text(text = label, style = TandemType.meta, color = TandemColors.ink2)
            }
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun DotRingIdlePreview() {
    DotRing(value = 43, maxValue = 100, unit = "%")
}
