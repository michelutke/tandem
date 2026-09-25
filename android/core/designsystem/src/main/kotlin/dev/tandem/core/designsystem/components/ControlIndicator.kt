@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemShapes
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType

/**
 * The accessibility-overlay pill "Mac is controlling · Stop", drawn above any app whenever remote
 * input is accepted (PRD invariant 8, ui-spec.md §5.2, §9.5, §10 `control.pill`).
 */
@Composable
fun ControlIndicator(
    onStop: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier =
            modifier
                .background(color = TandemColors.ink, shape = TandemShapes.pill)
                .padding(horizontal = TandemSpacing.lg, vertical = TandemSpacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text = "Mac is controlling", style = TandemType.meta, color = TandemColors.paper)
        Text(text = " · ", style = TandemType.meta, color = TandemColors.paper)
        Text(
            text = "Stop",
            style = TandemType.meta,
            color = TandemColors.signal,
            modifier = Modifier.clickable(onClick = onStop),
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun ControlIndicatorPreview() {
    ControlIndicator(onStop = {})
}
