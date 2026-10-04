package dev.tandem.app.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import dev.tandem.core.designsystem.components.FloatingToolbarItem
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
    selectedToolbarItem: FloatingToolbarItem,
    onToolbarItemSelected: (FloatingToolbarItem) -> Unit,
    onFixBattery: () -> Unit,
    onRotateKey: () -> Unit,
    onUnpair: () -> Unit,
    modifier: Modifier = Modifier,
    keySection: (@Composable () -> Unit)? = null,
) {
    var showUnpairDialog by remember { mutableStateOf(false) }

    TandemScaffold(
        title = "Settings.",
        state = "Paired with ${state.macName}.",
        modifier = modifier,
        toolbarItems = FloatingToolbarItem.entries,
        selectedToolbarItem = selectedToolbarItem,
        onToolbarItemSelected = onToolbarItemSelected,
    ) { padding ->
        SettingsRows(
            padding = padding,
            state = state,
            onFixBattery = onFixBattery,
            onRotateKey = onRotateKey,
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
    keySection: (@Composable () -> Unit)?,
    onUnpairClick: () -> Unit,
) {
    Column(modifier = Modifier.padding(padding).fillMaxWidth()) {
        SettingsRow(label = "Paired Mac", value = state.macName)
        HairlineRule()
        SettingsRow(
            label = "Battery",
            value = if (state.batteryRestricted) "Restricted" else "Unrestricted",
            actionLabel = if (state.batteryRestricted) "Fix" else null,
            onAction = onFixBattery,
            isError = state.batteryRestricted,
        )
        HairlineRule()
        if (keySection != null) {
            keySection()
        } else {
            SettingsRow(label = "Key", value = state.keyShortCode, actionLabel = "Rotate", onAction = onRotateKey)
        }
        HairlineRule()
        SettingsRow(
            label = "Unpair",
            value = null,
            isError = true,
            modifier = Modifier.clickable(onClick = onUnpairClick),
        )
    }
}

@Composable
@Suppress("LongParameterList") // row slots: label, value, optional action, error tint
private fun SettingsRow(
    label: String,
    value: String?,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: () -> Unit = {},
    isError: Boolean = false,
) {
    val accent = if (isError) TandemColors.alert else TandemColors.ink
    Row(
        modifier =
            modifier
                .fillMaxWidth()
                .padding(horizontal = TandemSpacing.screenPadding, vertical = TandemSpacing.rowVerticalPadding),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text = label, style = TandemType.rowTitle, color = accent, modifier = Modifier.weight(1f))
        if (value != null) {
            Text(
                text = value,
                style = TandemType.meta,
                color = if (isError) TandemColors.alert else TandemColors.ink2,
            )
        }
        if (actionLabel != null) {
            TextButton(onClick = onAction) {
                Text(text = actionLabel, style = TandemType.rowTitle, color = accent)
            }
        }
    }
}
