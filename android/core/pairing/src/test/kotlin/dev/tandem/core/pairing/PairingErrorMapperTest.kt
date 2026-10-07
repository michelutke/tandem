package dev.tandem.core.pairing

import dev.tandem.protocol.v1.PairRejectedReason
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class PairingErrorMapperTest {
    @Test
    fun macRejectsPairingHandshake_qrExpiredRefreshOnMac() {
        val reason = PairingFailure.Timeout
        val message = PairingErrorMapper.mapFailureReason(reason)
        assertEquals(PairingErrorMessage.QR_EXPIRED, message)
    }

    @Test
    fun pairRejectedByOwner_pairingDeclinedOnMac() {
        val reason = PairRejectedReason.PAIR_REJECTED_REASON_REJECTED_BY_OWNER
        val message = PairingErrorMapper.mapRejectionReason(reason)
        assertEquals(PairingErrorMessage.DECLINED, message)
    }

    @Test
    fun pinMismatch_trustErrorNotNetwork() {
        assertEquals(PairingErrorMessage.PIN_MISMATCH, PairingErrorMapper.mapFailureReason(PairingFailure.PinMismatch))
    }

    @Test
    fun identityUnavailable_distinctFromNetwork() {
        assertEquals(
            PairingErrorMessage.IDENTITY_UNAVAILABLE,
            PairingErrorMapper.mapFailureReason(PairingFailure.IdentityUnavailable),
        )
    }

    @Test
    fun allQrAddressesUnreachable_networkIsolationHint() {
        val reason = PairingFailure.AllAddressesUnreachable
        val message = PairingErrorMapper.mapFailureReason(reason)
        assertEquals(PairingErrorMessage.NETWORK, message)
    }

    @Test
    fun connectionLostDuringPairing_qrExpiredNotNetworkError() {
        val reason = PairingFailure.ConnectionLost
        val message = PairingErrorMapper.mapFailureReason(reason)
        assertEquals(PairingErrorMessage.QR_EXPIRED, message)
    }

    @Test
    fun pairRejectedUnavailable_qrExpiredRefreshOnMac() {
        val reason = PairRejectedReason.PAIR_REJECTED_REASON_PAIRING_UNAVAILABLE
        val message = PairingErrorMapper.mapRejectionReason(reason)
        assertEquals(PairingErrorMessage.QR_EXPIRED, message)
    }

    @Test
    fun userCancelledConfirm_qrExpired() {
        val reason = PairingFailure.UserCancelled
        val message = PairingErrorMapper.mapFailureReason(reason)
        assertEquals(PairingErrorMessage.QR_EXPIRED, message)
    }

    @Test
    fun confirmationTimeout_qrExpired() {
        val reason = PairingFailure.ConfirmationTimeout
        val message = PairingErrorMapper.mapFailureReason(reason)
        assertEquals(PairingErrorMessage.QR_EXPIRED, message)
    }
}
