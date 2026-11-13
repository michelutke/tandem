package dev.tandem.app.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import dev.tandem.app.R
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.PillButton
import dev.tandem.core.designsystem.components.PillButtonVariant
import dev.tandem.core.designsystem.components.TandemScaffold

/**
 * Replaces the whole app on a trust failure (ui-spec.md §7.2 "Trust error", §8; §9.3 "Trust failures
 * are red, stop everything, and offer one action"; invariant 5, CLAUDE.md; E12-16, E20-17).
 * [UpdateNeeded][BlockedReason.UpdateNeeded] has nothing to pair again, so only Unpair is offered.
 */
@Composable
fun BlockedScreen(
    reason: BlockedReason,
    macName: String?,
    onPairAgain: () -> Unit,
    onUnpair: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val copy = reason.copy(macName)
    TandemScaffold(
        title = stringResource(R.string.blocked_title),
        state = copy.stateArg?.let { stringResource(copy.state, it) } ?: stringResource(copy.state),
        isError = true,
        modifier = modifier,
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = TandemSpacing.screenPadding),
            verticalArrangement = Arrangement.spacedBy(TandemSpacing.md),
        ) {
            Text(text = stringResource(copy.explanation), style = TandemType.body, color = TandemColors.ink2)
            Column(
                modifier = Modifier.weight(1f).fillMaxSize().padding(bottom = TandemSpacing.xxl),
                verticalArrangement = Arrangement.spacedBy(TandemSpacing.md, Alignment.Bottom),
            ) {
                if (reason != BlockedReason.UpdateNeeded) {
                    PillButton(text = stringResource(R.string.blocked_pair_again), onClick = onPairAgain)
                }
                PillButton(
                    text = stringResource(R.string.blocked_unpair),
                    onClick = onUnpair,
                    variant = PillButtonVariant.Secondary,
                )
            }
        }
    }
}

private class BlockedCopy(
    val state: Int,
    val explanation: Int,
    val stateArg: String? = null,
)

private fun BlockedReason.copy(macName: String?): BlockedCopy =
    when (this) {
        BlockedReason.PinMismatch -> {
            BlockedCopy(R.string.blocked_pin_state, R.string.blocked_pin_explanation)
        }

        BlockedReason.Revoked -> {
            BlockedCopy(
                R.string.blocked_revoked_state,
                R.string.blocked_revoked_explanation,
                macName ?: "The Mac",
            )
        }

        BlockedReason.UpdateNeeded -> {
            BlockedCopy(R.string.blocked_update_state, R.string.blocked_update_explanation)
        }
    }
