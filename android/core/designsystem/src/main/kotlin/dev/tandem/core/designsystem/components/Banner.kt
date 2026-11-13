@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
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
    detail: String? = null,
) {
    Row(
        modifier =
            modifier
                .fillMaxWidth()
                .background(color = TandemColors.alert.copy(alpha = 0.08f), shape = TandemShapes.button)
                .padding(horizontal = TandemSpacing.lg, vertical = TandemSpacing.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = message, style = TandemType.rowTitle, color = TandemColors.alert)
            if (detail != null) Text(text = detail, style = TandemType.meta, color = TandemColors.ink)
        }
        Button(
            onClick = onAction,
            modifier = Modifier.defaultMinSize(minHeight = TandemSpacing.touchTarget),
            shape = TandemShapes.pill,
            colors = ButtonDefaults.buttonColors(containerColor = TandemColors.ink, contentColor = TandemColors.paper),
        ) {
            Text(text = actionLabel, style = TandemType.rowTitle)
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun BannerPreview() {
    Banner(message = "Battery restricted.", actionLabel = "Fix", onAction = {
    }, detail = "Android may cut the link overnight.")
}
