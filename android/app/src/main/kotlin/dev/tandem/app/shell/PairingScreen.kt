package dev.tandem.app.shell

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import dev.tandem.core.designsystem.TandemColors
import dev.tandem.core.designsystem.TandemSpacing
import dev.tandem.core.designsystem.TandemType
import dev.tandem.core.designsystem.components.PillButton
import dev.tandem.core.designsystem.components.PillButtonVariant
import dev.tandem.core.designsystem.components.TandemScaffold
import dev.tandem.core.pairing.PairingErrorMapper
import dev.tandem.core.pairing.PairingErrorMessage
import dev.tandem.core.pairing.PairingFailure
import dev.tandem.core.pairing.PairingState

private const val CODE_GROUP = 3

/**
 * The pairing screens after a scan (E20-26, ui-spec §7.2 Confirm / Declined): progress while
 * connecting, the "Same code on both?" confirmation, and a fail-closed error with one action.
 * The code is shown only once the Mac has accepted ([PairingState.AwaitingUserConfirm]).
 */
@Composable
fun PairingScreen(
    state: PairingState,
    onCodesMatch: () -> Unit,
    onCodesDontMatch: () -> Unit,
    onScanAgain: () -> Unit,
    modifier: Modifier = Modifier,
) {
    when (state) {
        is PairingState.AwaitingUserConfirm -> {
            ConfirmContent(state, onCodesMatch, onCodesDontMatch, modifier)
        }

        PairingState.Paired -> {
            TandemScaffold(title = "Paired.", state = "Opening Home…", modifier = modifier) {}
        }

        PairingState.Idle,
        PairingState.Connecting,
        PairingState.AwaitingProofSent,
        is PairingState.AwaitingAccept,
        -> {
            TandemScaffold(title = "Pairing.", state = "Connecting…", modifier = modifier) {}
        }

        is PairingState.Rejected,
        is PairingState.Failed,
        -> {
            val (title, detail) = checkNotNull(pairingErrorText(state))
            TandemScaffold(title = title, state = detail, isError = true, modifier = modifier) { padding ->
                Column(modifier = Modifier.padding(padding).padding(horizontal = TandemSpacing.screenPadding)) {
                    PillButton(text = "Scan again", onClick = onScanAgain)
                }
            }
        }
    }
}

@Composable
private fun ConfirmContent(
    state: PairingState.AwaitingUserConfirm,
    onCodesMatch: () -> Unit,
    onCodesDontMatch: () -> Unit,
    modifier: Modifier,
) {
    TandemScaffold(title = "${state.macName}.", state = "Same code on both?", modifier = modifier) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = TandemSpacing.screenPadding),
            verticalArrangement = Arrangement.spacedBy(TandemSpacing.md, Alignment.CenterVertically),
        ) {
            Text(
                text = state.code.chunked(CODE_GROUP).joinToString(" "),
                style = TandemType.displayNumeralCode,
                color = TandemColors.ink,
            )
            PillButton(text = "Codes match", onClick = onCodesMatch)
            PillButton(text = "They don't match", onClick = onCodesDontMatch, variant = PillButtonVariant.Secondary)
        }
    }
}

/** Title and detail for a terminal failed or rejected [state] (ui-spec §10 copy); null otherwise. */
internal fun pairingErrorText(state: PairingState): Pair<String, String>? =
    when (state) {
        is PairingState.Rejected -> errorText(PairingErrorMapper.mapRejectionReason(state.reason))
        is PairingState.Failed -> failureText(state.reason)
        else -> null
    }

private fun failureText(reason: PairingFailure): Pair<String, String> =
    if (reason == PairingFailure.UserCancelled) {
        "Not paired." to "The codes didn't match."
    } else {
        errorText(PairingErrorMapper.mapFailureReason(reason))
    }

private fun errorText(message: PairingErrorMessage): Pair<String, String> =
    when (message) {
        PairingErrorMessage.DECLINED -> "Declined." to "The Mac said no."
        PairingErrorMessage.NETWORK -> "Can't reach the Mac." to "Same Wi-Fi?"
        PairingErrorMessage.PIN_MISMATCH -> "Not trusted." to "This Mac's identity changed. Pair again."
        PairingErrorMessage.QR_EXPIRED -> "Code expired." to "Scan a new one."
    }
