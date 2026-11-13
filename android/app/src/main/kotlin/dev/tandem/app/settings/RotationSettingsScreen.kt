package dev.tandem.app.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import dev.tandem.app.R
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
                    .clickable(enabled = actionEnabled, onClick = onRotate)
                    .padding(horizontal = TandemSpacing.screenPadding, vertical = TandemSpacing.rowVerticalPadding),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = stringResource(R.string.settings_key),
                    style = TandemType.rowTitle,
                    color = TandemColors.ink,
                )
                Text(text = currentFingerprint, style = TandemType.metaMono, color = TandemColors.ink)
            }
            Text(
                text = stringResource(R.string.settings_key_rotate),
                style = TandemType.meta,
                color = TandemColors.ink2,
            )
        }
        StatusLine(state = state, disabledReason = disabledReason, onDismissResult = onDismissResult)
    }

    if (state == RotationState.Confirming) {
        TandemDialog(
            title = stringResource(R.string.settings_rotate_title),
            text = stringResource(R.string.settings_rotate_text),
            confirmText = stringResource(R.string.settings_key_rotate),
            dismissText = stringResource(R.string.dialog_cancel),
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
            RotationState.InProgress -> {
                stringResource(R.string.settings_rotate_in_progress) to TandemColors.ink
            }

            is RotationState.Success -> {
                stringResource(R.string.settings_rotate_success, state.newFingerprint) to TandemColors.ink
            }

            is RotationState.Failed -> {
                stringResource(R.string.settings_rotate_failed, state.reason) to
                    TandemColors.alert
            }

            RotationState.Idle, RotationState.Confirming -> {
                (disabledReason ?: "") to TandemColors.ink
            }
        }
    if (text.isEmpty()) return
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = TandemSpacing.screenPadding),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text = text, style = TandemType.meta, color = color, modifier = Modifier.weight(1f))
        if (state is RotationState.Success || state is RotationState.Failed) {
            TextButton(onClick = onDismissResult) {
                Text(
                    text = stringResource(R.string.settings_rotate_ok),
                    style = TandemType.rowTitle,
                    color = TandemColors.ink,
                )
            }
        }
    }
}
