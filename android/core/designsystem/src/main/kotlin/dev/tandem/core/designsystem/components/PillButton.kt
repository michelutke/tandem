@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.fillMaxWidth
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
import dev.tandem.core.designsystem.TandemType

/** The single-primary-action pattern (ui-spec.md §2, §5.2): full-width, `button` radius (pill). */
@Composable
fun PillButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    variant: PillButtonVariant = PillButtonVariant.Primary,
    enabled: Boolean = true,
) {
    when (variant) {
        PillButtonVariant.Primary -> {
            Button(
                onClick = onClick,
                modifier = modifier.fillMaxWidth(),
                enabled = enabled,
                shape = TandemShapes.button,
                colors =
                    ButtonDefaults.buttonColors(
                        containerColor = TandemColors.ink,
                        contentColor = TandemColors.paper,
                    ),
            ) { Text(text = text, style = TandemType.rowTitle) }
        }

        PillButtonVariant.Destructive -> {
            Button(
                onClick = onClick,
                modifier = modifier.fillMaxWidth(),
                enabled = enabled,
                shape = TandemShapes.button,
                colors =
                    ButtonDefaults.buttonColors(
                        containerColor = TandemColors.alert,
                        contentColor = TandemColors.paper,
                    ),
            ) { Text(text = text, style = TandemType.rowTitle) }
        }

        PillButtonVariant.Secondary -> {
            OutlinedButton(
                onClick = onClick,
                modifier = modifier.fillMaxWidth(),
                enabled = enabled,
                shape = TandemShapes.button,
                border = BorderStroke(1.dp, TandemColors.line),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = TandemColors.ink),
            ) { Text(text = text, style = TandemType.rowTitle) }
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun PillButtonPrimaryPreview() {
    PillButton(text = "Codes match", onClick = {})
}

@Preview(showBackground = true)
@Composable
private fun PillButtonDestructivePreview() {
    PillButton(text = "Unpair", onClick = {}, variant = PillButtonVariant.Destructive)
}

@Preview(showBackground = true)
@Composable
private fun PillButtonSecondaryPreview() {
    PillButton(text = "They don't match", onClick = {}, variant = PillButtonVariant.Secondary)
}
