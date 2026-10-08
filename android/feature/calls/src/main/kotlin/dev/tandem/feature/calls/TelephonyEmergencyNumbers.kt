package dev.tandem.feature.calls

import android.telephony.PhoneNumberUtils
import android.telephony.TelephonyManager

/** Production [EmergencyNumbers]: the telephony stack's own list, plus the framework's static check. */
class TelephonyEmergencyNumbers(
    private val telephonyManager: TelephonyManager,
) : EmergencyNumbers {
    override fun isEmergency(address: String): Boolean =
        try {
            telephonyManager.isEmergencyNumber(address) || PhoneNumberUtils.isEmergencyNumber(address)
        } catch (_: IllegalStateException) {
            PhoneNumberUtils.isEmergencyNumber(address)
        }
}
