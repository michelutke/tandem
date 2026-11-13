package dev.tandem.app.onboarding

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import dev.tandem.app.R
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.CheckBadge
import dev.tandem.core.designsystem.components.CompactPillButton
import dev.tandem.core.designsystem.components.HairlineRule
import dev.tandem.core.designsystem.components.PillButton
import dev.tandem.core.designsystem.components.TandemScaffold

/**
 * Onboarding · Permissions (ui-spec §7.2): numbered rows, each with a one-line reason and an
 * "Allow" pill, or "Granted" once on. Tapping "Allow" asks for that permission; a denied row stays
 * off and the feature stays disabled. SMS & calls offers "Skip" instead, since it is turned on
 * later. Grant state is re-read whenever the screen resumes, so it reflects dialogs and Settings
 * detours. "Continue" advances to the scan.
 */
@Composable
fun PermissionsScreen(
    viewModel: OnboardingViewModel,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val resumeCount by rememberResumeCount()
    val granted = resumeCount.let { viewModel.rows().associateWith(viewModel::isGranted) }

    TandemScaffold(
        title = stringResource(R.string.permissions_title),
        state = stringResource(R.string.permissions_state),
        modifier = modifier,
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            Column(modifier = Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                PermissionRows(viewModel, granted)
            }
            PillButton(
                text = stringResource(R.string.permissions_continue),
                onClick = onDone,
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
    var smsSkipped by rememberSaveable { mutableStateOf(false) }
    viewModel.rows().forEachIndexed { index, row ->
        val isGranted = granted.getValue(row)
        Row(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = TandemSpacing.screenPadding, vertical = TandemSpacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "%02d".format(index + 1),
                style = TandemType.metaMono,
                color = TandemColors.ink2,
                modifier = Modifier.width(INDEX_WIDTH).clearAndSetSemantics {},
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(text = stringResource(row.labelRes), style = TandemType.rowTitle, color = TandemColors.ink)
                Text(text = stringResource(row.reasonRes), style = TandemType.meta, color = TandemColors.ink)
            }
            PermissionAction(
                isGranted = isGranted,
                isSkippable = row == PermissionRow.SMS_AND_CALLS,
                isSkipped = smsSkipped,
                onAllow = { viewModel.allow(row) },
                onSkip = { smsSkipped = true },
            )
        }
        HairlineRule()
    }
}

@Composable
private fun PermissionAction(
    isGranted: Boolean,
    isSkippable: Boolean,
    isSkipped: Boolean,
    onAllow: () -> Unit,
    onSkip: () -> Unit,
) {
    when {
        isGranted -> {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CheckBadge()
                Text(
                    text = stringResource(R.string.permissions_granted),
                    style = TandemType.meta,
                    color = TandemColors.ink2,
                    modifier = Modifier.padding(start = TandemSpacing.sm),
                )
            }
        }

        isSkippable && isSkipped -> {}

        isSkippable -> {
            CompactPillButton(text = stringResource(R.string.permissions_skip), onClick = onSkip, filled = false)
        }

        else -> {
            CompactPillButton(text = stringResource(R.string.permissions_allow), onClick = onAllow)
        }
    }
}

private val INDEX_WIDTH = 28.dp
