package dev.tandem.feature.messaging

import android.app.Activity
import android.telephony.SmsManager
import dev.tandem.protocol.v1.SendSmsErrorCode

object SendResultMapper {
    /** RESULT_OK maps to UNSPECIFIED; NULL_PDU (no valid PDU for the destination) to INVALID_ADDRESS. */
    fun errorCode(resultCode: Int): SendSmsErrorCode =
        when (resultCode) {
            Activity.RESULT_OK -> SendSmsErrorCode.SEND_SMS_ERROR_CODE_UNSPECIFIED
            SmsManager.RESULT_ERROR_NO_SERVICE -> SendSmsErrorCode.SEND_SMS_ERROR_CODE_NO_SERVICE
            SmsManager.RESULT_ERROR_RADIO_OFF -> SendSmsErrorCode.SEND_SMS_ERROR_CODE_RADIO_OFF
            SmsManager.RESULT_ERROR_NULL_PDU -> SendSmsErrorCode.SEND_SMS_ERROR_CODE_INVALID_ADDRESS
            else -> SendSmsErrorCode.SEND_SMS_ERROR_CODE_GENERIC_FAILURE
        }
}
