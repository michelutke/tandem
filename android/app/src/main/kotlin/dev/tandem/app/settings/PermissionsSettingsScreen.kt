package dev.tandem.app.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import dev.tandem.app.R
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.HairlineRule
import dev.tandem.core.designsystem.components.NumberedRow
import dev.tandem.core.designsystem.components.TandemScaffold

/**
 * Settings › Permissions (ui-spec.md §2 "Numbered rows"): every permission the app uses with its
 * granted state. Tapping a row requests it, or opens the system page that manages it.
 */
@Composable
fun PermissionsSettingsScreen(
    statuses: List<PermissionStatus>,
    onSelect: (AppPermission) -> Unit,
    modifier: Modifier = Modifier,
) {
    TandemScaffold(
        title = stringResource(R.string.permissions_settings_title),
        state =
            stringResource(R.string.permissions_settings_state, statuses.count { it.granted }, statuses.size),
        modifier = modifier,
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
            statuses.forEachIndexed { index, status ->
                NumberedRow(
                    index = index + 1,
                    label = stringResource(status.permission.label),
                    trailingMeta = stringResource(status.toggleLabel()),
                    onClick = { onSelect(status.permission) },
                )
                Text(
                    text = stringResource(status.permission.reason),
                    style = TandemType.meta,
                    color = TandemColors.ink,
                    modifier = Modifier.padding(horizontal = TandemSpacing.screenPadding),
                )
                HairlineRule()
            }
        }
    }
}

private fun PermissionStatus.toggleLabel(): Int =
    if (granted) R.string.permissions_settings_on else R.string.permissions_settings_allow
