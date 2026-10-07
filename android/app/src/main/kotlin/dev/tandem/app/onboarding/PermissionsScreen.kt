package dev.tandem.app.onboarding

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.HairlineRule
import dev.tandem.core.designsystem.components.NumberedRow
import dev.tandem.core.designsystem.components.PillButton
import dev.tandem.core.designsystem.components.PillButtonVariant
import dev.tandem.core.designsystem.components.TandemScaffold

internal const val PERMISSIONS_TITLE = "Permissions."
internal const val PERMISSIONS_STATE = "Allow what you want to use."
internal const val PERMISSION_ON_LABEL = "On"
internal const val PERMISSION_ALLOW_LABEL = "Allow"
internal const val PERMISSIONS_SKIP_LABEL = "Skip"
internal const val PERMISSIONS_CONTINUE_LABEL = "Continue"

/**
 * Onboarding · Permissions (ui-spec §7.2): numbered rows, each with a one-line reason. Tapping a
 * row asks for that permission; a denied row stays off and the feature stays disabled. Grant
 * state is re-read whenever the screen resumes, so it reflects dialogs and Settings detours.
 * "Skip" (or "Continue" once everything is on) advances to the scan.
 */
@Composable
fun PermissionsScreen(
    viewModel: OnboardingViewModel,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var refreshCount by remember { mutableIntStateOf(0) }
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer =
            LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_RESUME) refreshCount++ }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    val granted = refreshCount.let { viewModel.rows().associateWith(viewModel::isGranted) }

    TandemScaffold(title = PERMISSIONS_TITLE, state = PERMISSIONS_STATE, modifier = modifier) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            Column(modifier = Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                PermissionRows(viewModel, granted)
            }
            PillButton(
                text = if (granted.values.all { it }) PERMISSIONS_CONTINUE_LABEL else PERMISSIONS_SKIP_LABEL,
                onClick = onDone,
                variant = PillButtonVariant.Secondary,
                modifier = Modifier.padding(TandemSpacing.screenPadding),
            )
        }
    }
}

@Composable
private fun PermissionRows(
    viewModel: OnboardingViewModel,
    granted: Map<PermissionRow, Boolean>,
) {
    viewModel.rows().forEachIndexed { index, row ->
        val isGranted = granted.getValue(row)
        NumberedRow(
            index = index + 1,
            label = row.label,
            trailingMeta = if (isGranted) PERMISSION_ON_LABEL else PERMISSION_ALLOW_LABEL,
            onClick = if (isGranted) null else ({ viewModel.allow(row) }),
        )
        Text(
            text = row.reason,
            style = TandemType.meta,
            color = TandemColors.ink2,
            modifier = Modifier.padding(horizontal = TandemSpacing.screenPadding),
        )
        HairlineRule()
    }
}
