package dev.tandem.feature.input

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.HairlineRule
import dev.tandem.core.designsystem.components.NumberedRow
import dev.tandem.core.designsystem.components.PillButton
import dev.tandem.core.designsystem.components.PillButtonVariant
import dev.tandem.core.designsystem.components.TandemScaffold

/**
 * Opt-in for remote input (ui-spec §7.2 "Remote control opt-in", E62-02): three facts, then Open
 * Accessibility settings or View only. [accessibilityState] is the E62-02 seam; once the service is
 * on the screen only confirms it. Input still only runs during a mirror session the user starts.
 */
@Composable
fun RemoteInputSettingsScreen(
    accessibilityState: AccessibilityStateSource,
    onOpenAccessibilitySettings: () -> Unit,
    onViewOnly: () -> Unit,
    modifier: Modifier = Modifier,
) {
    TandemScaffold(
        title = stringResource(R.string.remote_control_title),
        state = stringResource(R.string.remote_control_state),
        modifier = modifier,
    ) { padding ->
        Column(modifier = Modifier.padding(padding).fillMaxSize()) {
            HairlineRule()
            NumberedRow(index = 1, label = stringResource(R.string.remote_control_fact_accessibility))
            HairlineRule()
            NumberedRow(index = 2, label = stringResource(R.string.remote_control_fact_pill))
            HairlineRule()
            NumberedRow(index = 3, label = stringResource(R.string.remote_control_fact_off))
            HairlineRule()
            Column(
                modifier =
                    Modifier
                        .weight(1f)
                        .fillMaxSize()
                        .padding(horizontal = TandemSpacing.screenPadding)
                        .padding(bottom = TandemSpacing.xxl),
                verticalArrangement = Arrangement.spacedBy(TandemSpacing.md, Alignment.Bottom),
            ) {
                if (accessibilityState.isServiceEnabled()) {
                    Text(
                        text = stringResource(R.string.remote_control_enabled),
                        style = TandemType.body,
                        color = TandemColors.ink,
                    )
                } else {
                    PillButton(
                        text = stringResource(R.string.remote_control_open_accessibility),
                        onClick = onOpenAccessibilitySettings,
                    )
                }
                PillButton(
                    text = stringResource(R.string.remote_control_view_only),
                    onClick = onViewOnly,
                    variant = PillButtonVariant.Secondary,
                )
            }
        }
    }
}
