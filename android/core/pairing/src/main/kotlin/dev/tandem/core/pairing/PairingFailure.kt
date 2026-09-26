package dev.tandem.core.pairing

/**
 * Why a [PairingStateMachine] reached [PairingState.Failed] (E14-05; SPEC.md §2 "Dialing the QR
 * addresses (phone side)", "Frame order on a pairing-candidate connection", "Mutual confirmation").
 */
sealed class PairingFailure {
    /** Every literal address in the QR `a` field timed out (D-68: 3 s per address). */
    data object AllAddressesUnreachable : PairingFailure()

    /** No `PairAccepted`/`PairRejected` arrived within 120 s of sending `PairRequest` (SPEC.md §2). */
    data object Timeout : PairingFailure()

    /** The candidate connection closed while this machine was awaiting a peer message. */
    data object ConnectionLost : PairingFailure()

    /** The owner tapped Cancel on the post-`PairAccepted` code confirmation (D-16, AC-20). */
    data object UserCancelled : PairingFailure()

    /** 120 s elapsed in [PairingState.AwaitingUserConfirm] without the owner tapping "Codes match". */
    data object ConfirmationTimeout : PairingFailure()
}
