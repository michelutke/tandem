@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemShapes
import dev.tandem.core.designsystem.TandemType

/**
 * The M3E bottom-anchored confirmation dialog (ui-spec.md §5.2), e.g. "Unpair Pixel 9?" /
 * "Rotate key?". [confirmText] is red when [isDestructive] (ui-spec §2 "Single primary action").
 */
@Composable
@Suppress("LongParameterList") // dialog needs title/body/both actions plus destructive styling
fun TandemDialog(
    title: String,
    text: String,
    confirmText: String,
    onConfirm: () -> Unit,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    dismissText: String = "Cancel",
    isDestructive: Boolean = false,
) {
    AlertDialog(
        onDismissRequest = onDismissRequest,
        modifier = modifier,
        shape = TandemShapes.dialog,
        containerColor = TandemColors.paper,
        title = { Text(text = title, style = TandemType.rowTitle, color = TandemColors.ink) },
        text = { Text(text = text, style = TandemType.body, color = TandemColors.ink2) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(
                    text = confirmText,
                    style = TandemType.rowTitle,
                    color = if (isDestructive) TandemColors.alert else TandemColors.ink,
                )
            }
        },
        dismissButton = {
            TextButton(onClick = onDismissRequest) {
                Text(text = dismissText, style = TandemType.rowTitle, color = TandemColors.ink)
            }
        },
    )
}

@Preview(showBackground = true)
@Composable
private fun TandemDialogPreview() {
    TandemDialog(
        title = "Unpair Pixel 9?",
        text = "The Mac will no longer be able to reach this phone.",
        confirmText = "Unpair",
        onConfirm = {},
        onDismissRequest = {},
        isDestructive = true,
    )
}
