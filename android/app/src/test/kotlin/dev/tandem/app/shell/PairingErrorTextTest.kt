package dev.tandem.app.shell

import dev.tandem.app.R
import dev.tandem.core.pairing.PairingFailure
import dev.tandem.core.pairing.PairingState
import dev.tandem.protocol.v1.PairRejectedReason
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class PairingErrorTextTest {
    @Test
    fun pairingErrorText_declinedByOwner_saysMacSaidNo() {
        val state = PairingState.Rejected(PairRejectedReason.PAIR_REJECTED_REASON_REJECTED_BY_OWNER)

        assertEquals(R.string.pair_error_declined_title to R.string.pair_error_declined_state, pairingErrorText(state))
    }

    @Test
    fun pairingErrorText_unreachable_hintsSameWifi() {
        val state = PairingState.Failed(PairingFailure.AllAddressesUnreachable)

        assertEquals(R.string.scan_unreachable_title to R.string.scan_unreachable_state, pairingErrorText(state))
    }

    @Test
    fun pairingErrorText_identityUnavailable_saysKeyCouldNotBeCreated() {
        val state = PairingState.Failed(PairingFailure.IdentityUnavailable)

        assertEquals(R.string.pair_error_not_paired to R.string.pair_error_identity, pairingErrorText(state))
    }

    @Test
    fun pairingErrorText_userCancelled_saysNotPaired() {
        val state = PairingState.Failed(PairingFailure.UserCancelled)

        assertEquals(R.string.pair_error_not_paired to R.string.pair_error_codes_differ, pairingErrorText(state))
    }

    @Test
    fun pairingErrorText_expired_saysCodeExpired() {
        val state = PairingState.Failed(PairingFailure.Timeout)

        assertEquals(R.string.pair_error_expired_title to R.string.pair_error_expired_state, pairingErrorText(state))
    }

    @Test
    fun pairingErrorText_nonTerminalState_isNull() {
        assertEquals(null, pairingErrorText(PairingState.Connecting))
    }
}
