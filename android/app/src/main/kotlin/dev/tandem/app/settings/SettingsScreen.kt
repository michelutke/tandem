package dev.tandem.app.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import dev.tandem.app.R
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.HairlineRule
import dev.tandem.core.designsystem.components.M3ESwitch
import dev.tandem.core.designsystem.components.TandemDialog
import dev.tandem.core.designsystem.components.TandemScaffold

/**
 * The Settings tab (E20-19; ui-spec.md §7.2): hairline rows for Paired Mac, Battery (+ Fix when
 * restricted), Key (+ Rotate; [keySection] hosts the E70-06 rotation block) and a red Unpair row that
 * asks for confirmation before calling [onUnpair] (the E14-12 unpair action).
 */
@Composable
@Suppress("LongParameterList") // screen composes several independent, testable slots
fun SettingsScreen(
    state: SettingsState,
    onFixBattery: () -> Unit,
    onRotateKey: () -> Unit,
    onUnpair: () -> Unit,
    modifier: Modifier = Modifier,
    onOpenPermissions: () -> Unit = {},
    onAutoCaptureChange: (Boolean) -> Unit = {},
    onOpenAccessibilitySettings: () -> Unit = {},
    keySection: (@Composable () -> Unit)? = null,
) {
    var showUnpairDialog by remember { mutableStateOf(false) }
    var showAutoCaptureDialog by remember { mutableStateOf(false) }

    TandemScaffold(
        title = stringResource(R.string.settings_title),
        state = stringResource(R.string.settings_state, state.macName),
        modifier = modifier,
    ) { padding ->
        SettingsRows(
            padding = padding,
            state = state,
            onFixBattery = onFixBattery,
            onRotateKey = onRotateKey,
            onOpenPermissions = onOpenPermissions,
            onOpenAccessibilitySettings = onOpenAccessibilitySettings,
            onAutoCaptureToggle = {
                when {
                    !state.autoCapture -> showAutoCaptureDialog = true
                    !state.autoCaptureServiceOn -> onOpenAccessibilitySettings()
                    else -> onAutoCaptureChange(false)
                }
            },
            keySection = keySection,
            onUnpairClick = { showUnpairDialog = true },
        )
    }

    if (showAutoCaptureDialog) {
        TandemDialog(
            title = stringResource(R.string.settings_auto_capture_title),
            text = stringResource(R.string.settings_auto_capture_explain),
            confirmText = stringResource(R.string.settings_open_accessibility),
            dismissText = stringResource(R.string.dialog_cancel),
            onConfirm = {
                showAutoCaptureDialog = false
                onAutoCaptureChange(true)
                onOpenAccessibilitySettings()
            },
            onDismissRequest = { showAutoCaptureDialog = false },
        )
    }

    if (showUnpairDialog) {
        TandemDialog(
            title = stringResource(R.string.settings_unpair_title, state.macName),
            text = stringResource(R.string.settings_unpair_text),
            confirmText = stringResource(R.string.settings_unpair),
            dismissText = stringResource(R.string.dialog_cancel),
            onConfirm = {
                showUnpairDialog = false
                onUnpair()
            },
            onDismissRequest = { showUnpairDialog = false },
            isDestructive = true,
        )
    }
}

@Composable
@Suppress("LongParameterList") // one slot per row action
private fun SettingsRows(
    padding: PaddingValues,
    state: SettingsState,
    onFixBattery: () -> Unit,
    onRotateKey: () -> Unit,
    onOpenPermissions: () -> Unit,
    onAutoCaptureToggle: () -> Unit,
    onOpenAccessibilitySettings: () -> Unit,
    keySection: (@Composable () -> Unit)?,
    onUnpairClick: () -> Unit,
) {
    Column(modifier = Modifier.padding(padding).fillMaxWidth().verticalScroll(rememberScrollState())) {
        SettingsRow(
            label = stringResource(R.string.settings_paired_mac),
            subtitle = state.macName,
            trailing =
                stringResource(
                    if (state.connected) R.string.settings_connected else R.string.settings_not_connected,
                ),
        )
        HairlineRule()
        BatteryRow(state = state, onFixBattery = onFixBattery)
        HairlineRule()
        if (keySection != null) {
            keySection()
        } else {
            SettingsRow(
                label = stringResource(R.string.settings_key),
                subtitle = state.keyShortCode,
                trailing = stringResource(R.string.settings_key_rotate),
                onAction = onRotateKey,
                monoSubtitle = true,
            )
        }
        HairlineRule()
        AutoCaptureRow(state = state, onToggle = onAutoCaptureToggle)
        HairlineRule()
        if (!state.autoCapture && state.autoCaptureServiceOn) {
            SettingsRow(
                label = stringResource(R.string.settings_clipboard_access),
                subtitle = stringResource(R.string.settings_auto_capture_remove_access),
                trailing = stringResource(R.string.settings_open),
                onAction = onOpenAccessibilitySettings,
            )
            HairlineRule()
        }
        SettingsRow(
            label = stringResource(R.string.settings_permissions),
            subtitle = stringResource(R.string.settings_permissions_detail),
            trailing = stringResource(R.string.settings_permissions_review),
            onAction = onOpenPermissions,
        )
        HairlineRule()
        SettingsRow(label = stringResource(R.string.settings_unpair), isError = true, onAction = onUnpairClick)
        HairlineRule()
    }
}

@Composable
private fun BatteryRow(
    state: SettingsState,
    onFixBattery: () -> Unit,
) {
    SettingsRow(
        label = stringResource(R.string.settings_battery),
        subtitle =
            stringResource(
                if (state.batteryRestricted) {
                    R.string.settings_battery_restricted
                } else {
                    R.string.settings_battery_unrestricted
                },
            ),
        trailing =
            stringResource(
                if (state.batteryRestricted) R.string.battery_restricted_fix else R.string.settings_battery_ok,
            ),
        onAction = if (state.batteryRestricted) onFixBattery else null,
        isError = state.batteryRestricted,
    )
}

@Composable
private fun AutoCaptureRow(
    state: SettingsState,
    onToggle: () -> Unit,
) {
    val needsService = state.autoCapture && !state.autoCaptureServiceOn
    val checked = state.autoCapture && state.autoCaptureServiceOn
    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .toggleable(value = checked, role = Role.Switch, onValueChange = { onToggle() })
                .padding(horizontal = TandemSpacing.screenPadding, vertical = TandemSpacing.rowVerticalPadding),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = stringResource(R.string.settings_auto_capture_label),
                style = TandemType.rowTitle,
                color = TandemColors.ink,
            )
            if (needsService) {
                Text(
                    text = stringResource(R.string.settings_auto_capture_needs_service),
                    style = TandemType.meta,
                    color = TandemColors.ink,
                )
            }
        }
        M3ESwitch(checked = checked, onCheckedChange = null)
    }
}

@Composable
@Suppress("LongParameterList") // row slots: label, subtitle, trailing text, action, error tint
private fun SettingsRow(
    label: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    trailing: String? = null,
    onAction: (() -> Unit)? = null,
    isError: Boolean = false,
    monoSubtitle: Boolean = false,
) {
    val accent = if (isError) TandemColors.alert else TandemColors.ink
    Row(
        modifier =
            modifier
                .fillMaxWidth()
                .let { if (onAction != null) it.clickable(onClick = onAction) else it }
                .padding(horizontal = TandemSpacing.screenPadding, vertical = TandemSpacing.rowVerticalPadding),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = label, style = TandemType.rowTitle, color = accent)
            if (subtitle != null) {
                Text(
                    text = subtitle,
                    style = if (monoSubtitle) TandemType.metaMono else TandemType.meta,
                    color = if (isError) TandemColors.alert else TandemColors.ink,
                )
            }
        }
        if (trailing != null) {
            Text(
                text = trailing,
                style = TandemType.meta,
                color = if (isError) TandemColors.alert else TandemColors.ink2,
            )
        }
    }
}
