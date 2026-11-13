@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.drawCheckMark

/** A decorative signal-green ring with a check, always paired with a text label such as "Granted". */
@Composable
fun CheckBadge(
    modifier: Modifier = Modifier,
    size: Dp = 20.dp,
) {
    Canvas(modifier = modifier.size(size).clearAndSetSemantics {}) {
        drawCircle(color = TandemColors.signal, style = Stroke(width = this.size.minDimension * RING_WIDTH_FRACTION))
        drawCheckMark(color = TandemColors.signal)
    }
}

private const val RING_WIDTH_FRACTION = 0.08f

@Preview(showBackground = true)
@Composable
private fun CheckBadgePreview() {
    CheckBadge()
}
