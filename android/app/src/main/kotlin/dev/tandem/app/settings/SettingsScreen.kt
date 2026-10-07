package dev.tandem.app.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.HairlineRule
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
    keySection: (@Composable () -> Unit)? = null,
) {
    var showUnpairDialog by remember { mutableStateOf(false) }

    TandemScaffold(
        title = "Settings.",
        state = "Paired with ${state.macName}.",
        modifier = modifier,
    ) { padding ->
        SettingsRows(
            padding = padding,
            state = state,
            onFixBattery = onFixBattery,
            onRotateKey = onRotateKey,
            onOpenPermissions = onOpenPermissions,
            keySection = keySection,
            onUnpairClick = { showUnpairDialog = true },
        )
    }

    if (showUnpairDialog) {
        TandemDialog(
            title = "Unpair ${state.macName}?",
            text = "This phone and the Mac will forget each other.",
            confirmText = "Unpair",
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
    keySection: (@Composable () -> Unit)?,
    onUnpairClick: () -> Unit,
) {
    Column(modifier = Modifier.padding(padding).fillMaxWidth().verticalScroll(rememberScrollState())) {
        SettingsRow(label = "Paired Mac", subtitle = state.macName, trailing = state.connectionLabel)
        HairlineRule()
        SettingsRow(
            label = "Battery",
            subtitle = if (state.batteryRestricted) "Restricted" else "Unrestricted",
            trailing = if (state.batteryRestricted) "Fix" else "OK",
            onAction = if (state.batteryRestricted) onFixBattery else null,
            isError = state.batteryRestricted,
        )
        HairlineRule()
        if (keySection != null) {
            keySection()
        } else {
            SettingsRow(label = "Key", subtitle = state.keyShortCode, trailing = "Rotate", onAction = onRotateKey)
        }
        HairlineRule()
        SettingsRow(
            label = "Permissions",
            subtitle = "What Tandem can use",
            trailing = "Review",
            onAction = onOpenPermissions,
        )
        HairlineRule()
        SettingsRow(label = "Unpair", isError = true, onAction = onUnpairClick)
        HairlineRule()
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
                    style = TandemType.meta,
                    color = if (isError) TandemColors.alert else TandemColors.ink2,
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
