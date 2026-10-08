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
private const val MANUAL_MAC_TITLE = "Your Mac."
private const val MANUAL_MISMATCH_COPY =
    "If the codes differ, someone may be intercepting. Start pairing again on both devices."

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
            ConfirmContent(state.code, state.macName, state.manual, true, onCodesMatch, onCodesDontMatch, modifier)
        }

        is PairingState.ComparingCodes -> {
            ConfirmContent(state.code, MANUAL_MAC_TITLE, true, false, onCodesMatch, onCodesDontMatch, modifier)
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
    val title = if (manual) MANUAL_MAC_TITLE else "$macName."
    TandemScaffold(title = title, state = "Same code on both?", modifier = modifier) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = TandemSpacing.screenPadding),
            verticalArrangement = Arrangement.spacedBy(TandemSpacing.md, Alignment.CenterVertically),
        ) {
            if (manual) {
                Text(text = "Manual pairing", style = TandemType.meta, color = TandemColors.ink)
            }
            Text(
                text = code.chunked(CODE_GROUP).joinToString(" "),
                style = TandemType.displayNumeralCode,
                color = TandemColors.ink,
            )
            PillButton(text = "Codes match", onClick = onCodesMatch, enabled = matchEnabled)
            PillButton(
                text = if (manual) "Codes differ" else "They don't match",
                onClick = onCodesDontMatch,
                variant = PillButtonVariant.Secondary,
            )
            if (manual) {
                Text(text = MANUAL_MISMATCH_COPY, style = TandemType.meta, color = TandemColors.ink)
            }
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
        PairingErrorMessage.IDENTITY_UNAVAILABLE -> "Not paired." to "This phone's key couldn't be created."
        PairingErrorMessage.QR_EXPIRED -> "Code expired." to "Scan a new one."
        PairingErrorMessage.INCOMPATIBLE_KEY -> "Not paired." to "This Mac's key isn't supported."
        PairingErrorMessage.PROTOCOL_VIOLATION -> "Not paired." to "The Mac didn't answer as expected. Start again."
    }
