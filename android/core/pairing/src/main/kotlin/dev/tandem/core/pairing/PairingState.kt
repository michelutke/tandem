package dev.tandem.core.pairing

import dev.tandem.protocol.v1.PairRejectedReason

/**
 * Phone-side pairing-attempt lifecycle (E14-05; SPEC.md §2 "Pairing", aligned with the macOS twin's
 * `PairingWindow`, E14-02). Documented transitions, all driven by [PairingStateMachine]:
 *
 * [Idle] -[start]-> [Connecting] -[connector succeeds]-> [AwaitingProofSent]
 * -[`PairChallenge` received, `PairRequest` sent]-> [AwaitingAccept] -[`PairAccepted`]->
 * [AwaitingUserConfirm] -[owner taps "Codes match"]-> [Paired]
 *
 * [Rejected] is reached from [AwaitingAccept] on a received `PairRejected`. [Failed] is reached
 * from [Connecting] (every QR address unreachable), from [AwaitingProofSent]/[AwaitingAccept] (the
 * candidate connection dropping, or no result within 120 s of sending `PairRequest`), and from
 * [AwaitingUserConfirm] (owner Cancel, or 120 s without a tap) — never a silent return to [Idle].
 */
sealed class PairingState {
    /** Initial state; nothing dialed yet. */
    data object Idle : PairingState()

    /** Dialing the QR `a` addresses in order, 3 s per address (D-68). */
    data object Connecting : PairingState()

    /** A candidate connection is open; awaiting the Mac's `PairChallenge` (SPEC.md §2, Frame order). */
    data object AwaitingProofSent : PairingState()

    /**
     * `PairRequest` sent; awaiting `PairAccepted`/`PairRejected` for up to 120 s. [code] is the
     * 6-digit confirmation code (already computable from `secret`/both SPKIs/`cb`), shown to the
     * owner from this state on (SPEC.md §2, Mutual confirmation).
     */
    data class AwaitingAccept(
        val code: String,
    ) : PairingState()

    /**
     * `PairAccepted` received; the Mac already committed this phone's SPKI to its own trust store.
     * Awaiting the owner's "Codes match" (commits [PairingStateMachine.confirmCodesMatch]) or
     * Cancel ([PairingStateMachine.cancelConfirm]) for up to 120 s (SPEC.md §2, Mutual confirmation,
     * D-16, AC-20).
     */
    data class AwaitingUserConfirm(
        val code: String,
        val macName: String,
    ) : PairingState()

    /** The owner confirmed the code; the Mac's fingerprint is committed to this phone's trust store. */
    data object Paired : PairingState()

    /** The Mac sent `PairRejected`; this phone's trust store is unchanged. */
    data class Rejected(
        val reason: PairRejectedReason,
    ) : PairingState()

    /** See [PairingFailure] for why; this phone's trust store is unchanged. */
    data class Failed(
        val reason: PairingFailure,
    ) : PairingState()
}
