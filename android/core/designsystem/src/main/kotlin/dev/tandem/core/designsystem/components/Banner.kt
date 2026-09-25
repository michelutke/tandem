@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemShapes
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType

/** An alert-tinted inline banner with one action, e.g. "Battery restricted." + Fix (ui-spec §5.2). */
@Composable
fun Banner(
    message: String,
    actionLabel: String,
    onAction: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier =
            modifier
                .fillMaxWidth()
                .background(color = TandemColors.alert.copy(alpha = 0.08f), shape = TandemShapes.button)
                .padding(horizontal = TandemSpacing.lg, vertical = TandemSpacing.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = message,
            style = TandemType.rowTitle,
            color = TandemColors.alert,
            modifier = Modifier.weight(1f),
        )
        TextButton(onClick = onAction) {
            Text(text = actionLabel, style = TandemType.rowTitle, color = TandemColors.alert)
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun BannerPreview() {
    Banner(message = "Battery restricted.", actionLabel = "Fix", onAction = {})
}
