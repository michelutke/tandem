@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemShapes
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType

/**
 * A content-width pill for row actions ("Allow", "Skip", ui-spec §7.2 Permissions): filled ink when
 * [filled], outlined otherwise. Material keeps the 48 dp touch target around the visible pill.
 */
@Composable
fun CompactPillButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    filled: Boolean = true,
) {
    val padding = PaddingValues(horizontal = TandemSpacing.lg, vertical = TandemSpacing.sm)
    if (filled) {
        Button(
            onClick = onClick,
            modifier = modifier,
            shape = TandemShapes.button,
            contentPadding = padding,
            colors = ButtonDefaults.buttonColors(containerColor = TandemColors.ink, contentColor = TandemColors.paper),
        ) { Text(text = text, style = TandemType.rowTitle) }
    } else {
        OutlinedButton(
            onClick = onClick,
            modifier = modifier,
            shape = TandemShapes.button,
            contentPadding = padding,
            border = BorderStroke(1.dp, TandemColors.line),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = TandemColors.ink),
        ) { Text(text = text, style = TandemType.rowTitle) }
    }
}

@Preview(showBackground = true)
@Composable
private fun CompactPillButtonPreview() {
    CompactPillButton(text = "Allow", onClick = {})
}
