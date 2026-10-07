package dev.tandem.app.shell

import dev.tandem.core.pairing.PairingFailure
import dev.tandem.core.pairing.PairingState
import dev.tandem.protocol.v1.PairRejectedReason
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class PairingErrorTextTest {
    @Test
    fun pairingErrorText_declinedByOwner_saysMacSaidNo() {
        val state = PairingState.Rejected(PairRejectedReason.PAIR_REJECTED_REASON_REJECTED_BY_OWNER)

        assertEquals("Declined." to "The Mac said no.", pairingErrorText(state))
    }

    @Test
    fun pairingErrorText_unreachable_hintsSameWifi() {
        val state = PairingState.Failed(PairingFailure.AllAddressesUnreachable)

        assertEquals("Can't reach the Mac." to "Same Wi-Fi?", pairingErrorText(state))
    }

    @Test
    fun pairingErrorText_identityUnavailable_saysKeyCouldNotBeCreated() {
        val state = PairingState.Failed(PairingFailure.IdentityUnavailable)

        assertEquals("Not paired." to "This phone's key couldn't be created.", pairingErrorText(state))
    }

    @Test
    fun pairingErrorText_userCancelled_saysNotPaired() {
        val state = PairingState.Failed(PairingFailure.UserCancelled)

        assertEquals("Not paired." to "The codes didn't match.", pairingErrorText(state))
    }

    @Test
    fun pairingErrorText_expired_saysCodeExpired() {
        val state = PairingState.Failed(PairingFailure.Timeout)

        assertEquals("Code expired." to "Scan a new one.", pairingErrorText(state))
    }

    @Test
    fun pairingErrorText_nonTerminalState_isNull() {
        assertEquals(null, pairingErrorText(PairingState.Connecting))
    }
}
