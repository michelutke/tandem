package dev.tandem.app.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.TandemDialog

/** "Rotate key" block of Settings (E70-06; ui-spec.md §7.2): action row, confirm dialog, result line. */
@Composable
@Suppress("LongParameterList") // independent slots: state, values, and one callback per user action
fun RotationSettingsScreen(
    state: RotationState,
    currentFingerprint: String,
    actionEnabled: Boolean,
    disabledReason: String?,
    onRotate: () -> Unit,
    onConfirm: () -> Unit,
    onCancel: () -> Unit,
    onDismissResult: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = TandemSpacing.screenPadding, vertical = TandemSpacing.rowVerticalPadding),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Key",
                style = TandemType.rowTitle,
                color = TandemColors.ink,
                modifier = Modifier.weight(1f),
            )
            Text(text = currentFingerprint, style = TandemType.meta, color = TandemColors.ink2)
            TextButton(onClick = onRotate, enabled = actionEnabled) {
                Text(text = "Rotate", style = TandemType.rowTitle, color = TandemColors.ink)
            }
        }
        StatusLine(state = state, disabledReason = disabledReason, onDismissResult = onDismissResult)
    }

    if (state == RotationState.Confirming) {
        TandemDialog(
            title = "Rotate key?",
            text = "This phone gets a new key and the Mac is told to trust it.",
            confirmText = "Rotate",
            onConfirm = onConfirm,
            onDismissRequest = onCancel,
        )
    }
}

@Composable
private fun StatusLine(
    state: RotationState,
    disabledReason: String?,
    onDismissResult: () -> Unit,
) {
    val (text, color) =
        when (state) {
            RotationState.InProgress -> "Rotating key…" to TandemColors.ink2
            is RotationState.Success -> "New key ${state.newFingerprint}." to TandemColors.ink2
            is RotationState.Failed -> "${state.reason} Still using the current key." to TandemColors.alert
            RotationState.Idle, RotationState.Confirming -> (disabledReason ?: "") to TandemColors.ink2
        }
    if (text.isEmpty()) return
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = TandemSpacing.screenPadding),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text = text, style = TandemType.meta, color = color, modifier = Modifier.weight(1f))
        if (state is RotationState.Success || state is RotationState.Failed) {
            TextButton(onClick = onDismissResult) {
                Text(text = "OK", style = TandemType.rowTitle, color = TandemColors.ink)
            }
        }
    }
}
