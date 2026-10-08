package dev.tandem.core.pairing

import kotlinx.coroutines.flow.StateFlow

/**
 * One pairing attempt as the shell drives it: the QR [PairingStateMachine] or the manual
 * [ManualPairingStateMachine] (E73-03). Both share [PairingState] and the owner's two actions, so
 * the shell and its screens treat them alike.
 */
interface PairingAttempt {
    val state: StateFlow<PairingState>

    /** Idle -> Connecting; no-op if already started. */
    fun start()

    /** The owner tapped "Codes match". No-op until the Mac has accepted. */
    suspend fun confirmCodesMatch()

    /** The owner reported a mismatch or cancelled. Commits nothing. */
    fun cancelConfirm()

    /** Callers own the attempt's lifetime and MUST call this once done with it. */
    fun close()
}
