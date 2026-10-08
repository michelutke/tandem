package dev.tandem.core.pairing

import dev.tandem.protocol.v1.PairRejectedReason

/**
 * User-facing error message kind for pairing failures (E14-17).
 */
enum class PairingErrorMessage {
    /** QR expired, refresh on Mac */
    QR_EXPIRED,

    /** Pairing declined on Mac */
    DECLINED,

    /** Can't reach your Mac */
    NETWORK,

    /** Peer identity is not the scanned one; re-pair, never retry */
    PIN_MISMATCH,

    /** This phone's own identity key is unavailable; nothing was dialed */
    IDENTITY_UNAVAILABLE,

    /** A manual-pairing message was missing, out of order or failed verification; nothing was pinned */
    PROTOCOL_VIOLATION,

    /** The Mac's TLS key is not a supported P-256 key, so it can't be paired; nothing was pinned */
    INCOMPATIBLE_KEY,
}

/**
 * Maps pairing failure reasons to user-facing error message kinds (E14-17).
 */
object PairingErrorMapper {
    fun mapFailureReason(reason: PairingFailure): PairingErrorMessage =
        when (reason) {
            is PairingFailure.AllAddressesUnreachable -> PairingErrorMessage.NETWORK
            is PairingFailure.Timeout -> PairingErrorMessage.QR_EXPIRED
            is PairingFailure.ConnectionLost -> PairingErrorMessage.QR_EXPIRED
            is PairingFailure.UserCancelled -> PairingErrorMessage.QR_EXPIRED
            is PairingFailure.ConfirmationTimeout -> PairingErrorMessage.QR_EXPIRED
            is PairingFailure.ChallengeTimeout -> PairingErrorMessage.NETWORK
            is PairingFailure.MalformedChallenge -> PairingErrorMessage.QR_EXPIRED
            is PairingFailure.PinMismatch -> PairingErrorMessage.PIN_MISMATCH
            is PairingFailure.IdentityUnavailable -> PairingErrorMessage.IDENTITY_UNAVAILABLE
            is PairingFailure.ProtocolViolation -> PairingErrorMessage.PROTOCOL_VIOLATION
            is PairingFailure.IncompatibleMacKey -> PairingErrorMessage.INCOMPATIBLE_KEY
        }

    fun mapRejectionReason(reason: PairRejectedReason): PairingErrorMessage =
        when (reason) {
            PairRejectedReason.PAIR_REJECTED_REASON_REJECTED_BY_OWNER -> PairingErrorMessage.DECLINED
            PairRejectedReason.PAIR_REJECTED_REASON_PAIRING_UNAVAILABLE -> PairingErrorMessage.QR_EXPIRED
            else -> PairingErrorMessage.QR_EXPIRED
        }
}
