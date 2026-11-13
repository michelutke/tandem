package dev.tandem.app.shell

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.tandem.app.R
import dev.tandem.core.designsystem.DarkSystemBars
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemShapes
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.DotMark
import dev.tandem.core.designsystem.components.PillButton
import dev.tandem.core.designsystem.components.PillButtonVariant
import dev.tandem.core.designsystem.components.TandemScaffold
import dev.tandem.core.pairing.PairingErrorMapper
import dev.tandem.core.pairing.PairingErrorMessage
import dev.tandem.core.pairing.PairingFailure
import dev.tandem.core.pairing.PairingState

private const val CODE_GROUP = 3
private val CODE_MIN_SIZE = 32.sp

/**
 * The pairing screens after a scan (E20-26, ui-spec §7.2 Confirm / Declined): progress while
 * connecting, the "Same code on both?" confirmation, and a fail-closed error with one action.
 * The code is shown only once the Mac has accepted ([PairingState.AwaitingUserConfirm]).
 */
@Composable
@Suppress("LongParameterList") // one slot per pairing action plus the paired Mac's name
fun PairingScreen(
    state: PairingState,
    onCodesMatch: () -> Unit,
    onCodesDontMatch: () -> Unit,
    onScanAgain: () -> Unit,
    modifier: Modifier = Modifier,
    pairedMacName: String? = null,
    onDone: () -> Unit = {},
) {
    val insetModifier = modifier.safeDrawingPadding()
    when (state) {
        is PairingState.AwaitingUserConfirm -> {
            ConfirmContent(state.code, state.macName, state.manual, true, onCodesMatch, onCodesDontMatch, insetModifier)
        }

        is PairingState.ComparingCodes -> {
            ConfirmContent(state.code, "", true, false, onCodesMatch, onCodesDontMatch, insetModifier)
        }

        PairingState.Paired -> {
            PairedContent(pairedMacName, onDone, insetModifier)
        }

        PairingState.Idle,
        PairingState.Connecting,
        PairingState.AwaitingProofSent,
        is PairingState.AwaitingAccept,
        -> {
            TandemScaffold(
                title = stringResource(R.string.pair_progress_title),
                state = stringResource(R.string.pair_progress_state),
                modifier = insetModifier,
            ) {}
        }

        is PairingState.Rejected,
        is PairingState.Failed,
        -> {
            val (title, detail) = checkNotNull(pairingErrorText(state))
            if (pairingErrorMessage(state) == PairingErrorMessage.NETWORK) {
                ScanUnreachableScreen(onTryAgain = onScanAgain, modifier = modifier)
                return
            }
            TandemScaffold(
                title = stringResource(title),
                state = stringResource(detail),
                isError = true,
                modifier = insetModifier,
            ) { padding ->
                Column(modifier = Modifier.padding(padding).padding(horizontal = TandemSpacing.screenPadding)) {
                    PillButton(text = stringResource(R.string.pair_scan_again), onClick = onScanAgain)
                }
            }
        }
    }
}

@Composable
private fun PairedContent(
    macName: String?,
    onDone: () -> Unit,
    modifier: Modifier,
) {
    TandemScaffold(
        title = stringResource(R.string.pair_paired_title),
        state =
            stringResource(
                R.string.pair_paired_state,
                macName ?: stringResource(R.string.pair_paired_unknown_name),
            ),
        modifier = modifier,
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).padding(TandemSpacing.screenPadding)) {
            DotMark()
            Spacer(Modifier.weight(1f))
            PillButton(text = stringResource(R.string.pair_done), onClick = onDone)
        }
    }
}

@Composable
@Suppress("LongParameterList") // one slot per piece of the confirm screen
private fun ConfirmContent(
    code: String,
    macName: String,
    manual: Boolean,
    matchEnabled: Boolean,
    onCodesMatch: () -> Unit,
    onCodesDontMatch: () -> Unit,
    modifier: Modifier,
) {
    val title = if (manual) stringResource(R.string.pair_manual_mac_title) else "$macName."
    TandemScaffold(title = title, state = stringResource(R.string.pair_confirm_state), modifier = modifier) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = TandemSpacing.screenPadding)) {
            if (manual) {
                Text(
                    text = stringResource(R.string.pair_manual_label),
                    style = TandemType.meta,
                    color = TandemColors.ink,
                    modifier = Modifier.padding(bottom = TandemSpacing.md),
                )
            }
            Column(
                modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = code.spokenDigits() },
            ) {
                code.chunked(CODE_GROUP).forEach { group -> CodeGroup(group) }
            }
            Spacer(Modifier.weight(1f))
            if (manual) {
                Text(
                    text = stringResource(R.string.pair_manual_mismatch),
                    style = TandemType.meta,
                    color = TandemColors.ink,
                    modifier = Modifier.padding(bottom = TandemSpacing.md),
                )
            }
            PillButton(
                text = stringResource(R.string.pair_codes_match),
                onClick = onCodesMatch,
                enabled = matchEnabled,
            )
            PillButton(
                text = stringResource(if (manual) R.string.pair_codes_differ else R.string.pair_codes_dont_match),
                onClick = onCodesDontMatch,
                variant = PillButtonVariant.Secondary,
                modifier = Modifier.padding(top = TandemSpacing.sm, bottom = TandemSpacing.screenPadding),
            )
        }
    }
}

@Composable
private fun CodeGroup(group: String) {
    BasicText(
        text = group,
        style = TandemType.displayNumeralCode,
        color = { TandemColors.ink },
        maxLines = 1,
        autoSize =
            TextAutoSize.StepBased(
                minFontSize = CODE_MIN_SIZE,
                maxFontSize = TandemType.displayNumeralCode.fontSize,
            ),
    )
}

private fun String.spokenDigits(): String = chunked(CODE_GROUP).joinToString(", ") { it.toList().joinToString(" ") }

private fun pairingErrorMessage(state: PairingState): PairingErrorMessage? =
    when (state) {
        is PairingState.Rejected -> {
            PairingErrorMapper.mapRejectionReason(state.reason)
        }

        is PairingState.Failed -> {
            if (state.reason ==
                PairingFailure.UserCancelled
            ) {
                null
            } else {
                PairingErrorMapper.mapFailureReason(state.reason)
            }
        }

        else -> {
            null
        }
    }

/** Dark "Can't reach the Mac." state (ui-spec §7.2 Scan · Mac unreachable): hotspot hint and Try again. */
@Composable
private fun ScanUnreachableScreen(
    onTryAgain: () -> Unit,
    modifier: Modifier = Modifier,
) {
    DarkSystemBars()
    Surface(modifier = modifier.fillMaxSize(), color = TandemColors.paperDark) {
        Column(modifier = Modifier.fillMaxSize().safeDrawingPadding().padding(TandemSpacing.screenPadding)) {
            Text(
                text = stringResource(R.string.scan_unreachable_title),
                style = TandemType.titleEmphasis,
                color = TandemColors.inkOnDark,
            )
            Text(
                text = stringResource(R.string.scan_unreachable_state),
                style = TandemType.titleState,
                color = TandemColors.inkOnDark.copy(alpha = 0.7f),
            )
            Spacer(Modifier.weight(1f))
            Text(
                text = stringResource(R.string.scan_unreachable_hint),
                style = TandemType.meta,
                color = TandemColors.inkOnDark.copy(alpha = 0.7f),
                modifier = Modifier.fillMaxWidth().padding(bottom = TandemSpacing.md),
            )
            OutlinedButton(
                onClick = onTryAgain,
                modifier = Modifier.fillMaxWidth(),
                shape = TandemShapes.button,
                border = BorderStroke(1.dp, TandemColors.inkOnDark.copy(alpha = 0.3f)),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = TandemColors.inkOnDark),
            ) {
                Text(text = stringResource(R.string.scan_try_again), style = TandemType.rowTitle)
            }
        }
    }
}

/** String resources of the title and detail for a failed or rejected [state] (ui-spec §10 copy); null otherwise. */
internal fun pairingErrorText(state: PairingState): Pair<Int, Int>? =
    when (state) {
        is PairingState.Rejected -> errorText(PairingErrorMapper.mapRejectionReason(state.reason))
        is PairingState.Failed -> failureText(state.reason)
        else -> null
    }

private fun failureText(reason: PairingFailure): Pair<Int, Int> =
    if (reason == PairingFailure.UserCancelled) {
        R.string.pair_error_not_paired to R.string.pair_error_codes_differ
    } else {
        errorText(PairingErrorMapper.mapFailureReason(reason))
    }

private fun errorText(message: PairingErrorMessage): Pair<Int, Int> =
    when (message) {
        PairingErrorMessage.DECLINED -> R.string.pair_error_declined_title to R.string.pair_error_declined_state
        PairingErrorMessage.NETWORK -> R.string.scan_unreachable_title to R.string.scan_unreachable_state
        PairingErrorMessage.PIN_MISMATCH -> R.string.pair_error_not_trusted to R.string.pair_error_pin_mismatch
        PairingErrorMessage.IDENTITY_UNAVAILABLE -> R.string.pair_error_not_paired to R.string.pair_error_identity
        PairingErrorMessage.QR_EXPIRED -> R.string.pair_error_expired_title to R.string.pair_error_expired_state
        PairingErrorMessage.INCOMPATIBLE_KEY -> R.string.pair_error_not_paired to R.string.pair_error_incompatible_key
        PairingErrorMessage.PROTOCOL_VIOLATION -> R.string.pair_error_not_paired to R.string.pair_error_protocol
    }
