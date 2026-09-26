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
        }

    fun mapRejectionReason(reason: PairRejectedReason): PairingErrorMessage =
        when (reason) {
            PairRejectedReason.PAIR_REJECTED_REASON_REJECTED_BY_OWNER -> PairingErrorMessage.DECLINED
            PairRejectedReason.PAIR_REJECTED_REASON_PAIRING_UNAVAILABLE -> PairingErrorMessage.QR_EXPIRED
            else -> PairingErrorMessage.QR_EXPIRED
        }
}
