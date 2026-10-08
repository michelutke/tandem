package dev.tandem.feature.calls

import android.telecom.PhoneAccountHandle

/**
 * Starts the call behind the "Tap to call" notification. A revoked CALL_PHONE or READ_PHONE_STATE
 * surfaces as a [SecurityException]; it is reported through [onFailure] instead of crashing the
 * trampoline activity.
 */
class TapToCallLauncher(
    private val accountFor: (subscriptionId: Int) -> PhoneAccountHandle?,
    private val start: (address: String, account: PhoneAccountHandle?) -> Unit,
    private val onFailure: () -> Unit,
) {
    fun place(
        address: String?,
        subscriptionId: Int,
    ) {
        if (address.isNullOrEmpty()) return
        try {
            start(address, accountFor(subscriptionId))
        } catch (_: SecurityException) {
            onFailure()
        }
    }
}
