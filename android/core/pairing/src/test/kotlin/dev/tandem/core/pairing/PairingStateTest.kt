package dev.tandem.core.pairing

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Confirmation-code redaction (E14-05 finding 8; invariant 7: logs never contain secrets).
 * [PairingState.AwaitingAccept]/[PairingState.AwaitingUserConfirm] carry the confirmation code
 * derived from the pairing secret, so their `toString()` must never print it.
 */
class PairingStateTest {
    private val code = "013799"

    @Test
    fun awaitingAccept_toString_redactsConfirmationCode() {
        val state = PairingState.AwaitingAccept(code)

        assertFalse(state.toString().contains(code))
    }

    @Test
    fun awaitingUserConfirm_toString_redactsConfirmationCodeButKeepsMacName() {
        val state = PairingState.AwaitingUserConfirm(code, "Study Mac")

        assertFalse(state.toString().contains(code))
        assertTrue(state.toString().contains("Study Mac"))
    }
}
