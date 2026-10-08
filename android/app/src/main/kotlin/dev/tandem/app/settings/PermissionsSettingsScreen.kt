package dev.tandem.app.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import dev.tandem.app.onboarding.PERMISSION_ALLOW_LABEL
import dev.tandem.app.onboarding.PERMISSION_ON_LABEL
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.HairlineRule
import dev.tandem.core.designsystem.components.NumberedRow
import dev.tandem.core.designsystem.components.TandemScaffold

internal const val PERMISSIONS_SETTINGS_TITLE = "Permissions."

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
        title = PERMISSIONS_SETTINGS_TITLE,
        state = "${statuses.count { it.granted }} of ${statuses.size} allowed.",
        modifier = modifier,
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
            statuses.forEachIndexed { index, status ->
                NumberedRow(
                    index = index + 1,
                    label = status.permission.label,
                    trailingMeta = if (status.granted) PERMISSION_ON_LABEL else PERMISSION_ALLOW_LABEL,
                    onClick = { onSelect(status.permission) },
                )
                Text(
                    text = status.permission.reason,
                    style = TandemType.meta,
                    color = TandemColors.ink2,
                    modifier = Modifier.padding(horizontal = TandemSpacing.screenPadding),
                )
                HairlineRule()
            }
        }
    }
}
