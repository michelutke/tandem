@file:Suppress("MagicNumber", "UnusedPrivateMember") // Canvas sizing, preview data (ui-spec.md §5.2).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.drawColumnDots
import dev.tandem.core.designsystem.tandemAnimateFloatAsState
import kotlin.math.roundToInt

/**
 * The activity dot chart (ui-spec.md §5.2, §7.2 Activity: "Last 7 days"): one dot column per
 * period, metadata-only (invariant 4). Carries a single TalkBack description of the values.
 */
@Composable
fun DotChart(
    values: List<Int>,
    labels: List<String>,
    modifier: Modifier = Modifier,
    dotsPerColumn: Int = 7,
) {
    val maxValue = (values.maxOrNull() ?: 0).coerceAtLeast(1)

    Row(
        modifier =
            modifier.clearAndSetSemantics {
                contentDescription = labels.zip(values).joinToString(", ") { (label, value) -> "$label: $value" }
            },
    ) {
        values.forEachIndexed { index, value ->
            val fraction = (value.toFloat() / maxValue.toFloat()).coerceIn(0f, 1f)
            val animatedFraction by tandemAnimateFloatAsState(targetValue = fraction)
            val litDots = (animatedFraction * dotsPerColumn).roundToInt()

            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Canvas(modifier = Modifier.width(16.dp).height((dotsPerColumn * 12).dp)) {
                    drawColumnDots(maxDots = dotsPerColumn, litDots = litDots)
                }
                Text(
                    text = labels.getOrElse(index) { "" },
                    style = TandemType.metaMono,
                    color = TandemColors.ink2,
                )
            }
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun DotChartPreview() {
    DotChart(values = listOf(3, 5, 2, 7, 4, 1, 6), labels = listOf("M", "T", "W", "T", "F", "S", "S"))
}
