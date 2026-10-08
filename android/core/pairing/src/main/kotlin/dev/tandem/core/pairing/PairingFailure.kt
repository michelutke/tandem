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

    /** No `PairChallenge` arrived within 10 s of the candidate connection completing (SPEC.md §10). */
    data object ChallengeTimeout : PairingFailure()

    /**
     * The received `PairChallenge`, or one of the SPKIs observed on this handshake, failed
     * [dev.tandem.core.crypto.PairingProofException]'s precondition, so no proof/confirmation code
     * could be computed (SPEC.md §2 "Proof computation", invariant 6).
     */
    data object MalformedChallenge : PairingFailure()

    /** A dialed peer presented a key that is not the QR fingerprint (SPEC.md §5 row 2); never retried. */
    data object PinMismatch : PairingFailure()

    /** This phone's identity key could not be created or used, so no TLS dial was attempted (invariant 5). */
    data object IdentityUnavailable : PairingFailure()

    /**
     * The Mac sent a manual-pairing message that is missing, repeated, out of order or malformed,
     * or a `Reveal` that does not match its `Commitment` (ADR-008). Nothing was pinned.
     */
    data object ProtocolViolation : PairingFailure()
}
