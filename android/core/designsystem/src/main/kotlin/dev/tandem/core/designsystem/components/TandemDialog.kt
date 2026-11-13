@file:Suppress("UnusedPrivateMember") // @Preview composables are only invoked by Compose tooling (E00-31).

package dev.tandem.core.designsystem.components

import android.view.Gravity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemShapes
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType

/**
 * The M3E bottom-anchored confirmation dialog (ui-spec.md §5.2), e.g. "Unpair Pixel 9?" /
 * "Rotate key?": a 36 dp sheet pinned to the bottom with a title, grey body, a full-width
 * primary [PillButton] (red fill when [isDestructive], ui-spec §2 "Single primary action") over an
 * outlined secondary dismiss button.
 */
@Composable
@Suppress("LongParameterList") // dialog needs title/body/both actions plus destructive styling
fun TandemDialog(
    title: String,
    text: String,
    confirmText: String,
    dismissText: String,
    onConfirm: () -> Unit,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    isDestructive: Boolean = false,
) {
    Dialog(
        onDismissRequest = onDismissRequest,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        (LocalView.current.parent as? DialogWindowProvider)?.window?.setGravity(Gravity.BOTTOM)
        Surface(
            modifier = modifier.fillMaxWidth().padding(TandemSpacing.md),
            shape = TandemShapes.dialog,
            color = TandemColors.paper,
        ) {
            Column(modifier = Modifier.padding(TandemSpacing.xxl)) {
                Text(text = title, style = TandemType.titleEmphasis, color = TandemColors.ink)
                Text(
                    text = text,
                    style = TandemType.body,
                    color = TandemColors.ink2,
                    modifier = Modifier.padding(top = TandemSpacing.sm, bottom = TandemSpacing.xl),
                )
                PillButton(
                    text = confirmText,
                    onClick = onConfirm,
                    variant = if (isDestructive) PillButtonVariant.Destructive else PillButtonVariant.Primary,
                )
                PillButton(
                    text = dismissText,
                    onClick = onDismissRequest,
                    variant = PillButtonVariant.Secondary,
                    modifier = Modifier.padding(top = TandemSpacing.sm),
                )
            }
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun TandemDialogPreview() {
    TandemDialog(
        title = "Unpair Pixel 9?",
        text = "The Mac will no longer be able to reach this phone.",
        confirmText = "Unpair",
        dismissText = "Cancel",
        onConfirm = {},
        onDismissRequest = {},
        isDestructive = true,
    )
}
