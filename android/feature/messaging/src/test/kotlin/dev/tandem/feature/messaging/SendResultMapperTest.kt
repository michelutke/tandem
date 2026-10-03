package dev.tandem.feature.messaging

import android.app.Activity
import android.telephony.SmsManager
import dev.tandem.protocol.v1.SendSmsErrorCode
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class SendResultMapperTest {
    @Test
    fun sendResultMapper_eachSmsManagerResultCode_mapsToDistinctErrorCode() {
        val mapped =
            listOf(
                Activity.RESULT_OK,
                SmsManager.RESULT_ERROR_GENERIC_FAILURE,
                SmsManager.RESULT_ERROR_NO_SERVICE,
                SmsManager.RESULT_ERROR_NULL_PDU,
                SmsManager.RESULT_ERROR_RADIO_OFF,
            ).map(SendResultMapper::errorCode)

        assertEquals(5, mapped.toSet().size)
        assertEquals(
            SendSmsErrorCode.SEND_SMS_ERROR_CODE_NO_SERVICE,
            SendResultMapper.errorCode(SmsManager.RESULT_ERROR_NO_SERVICE),
        )
    }
}
