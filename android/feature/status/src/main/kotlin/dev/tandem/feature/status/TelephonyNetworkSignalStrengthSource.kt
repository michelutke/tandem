package dev.tandem.feature.status

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.telephony.SignalStrength
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOf

/**
 * Production [SignalStrengthSource] (E23-02): listens for `TelephonyManager` signal-strength
 * callbacks and emits [SignalStrength.level] (0-4). This app never requests `READ_PHONE_STATE`
 * (invariant 8 aside, PRD keeps this feature permission-free), so when that permission is not
 * held -- which, given that, is always -- this emits a single `null` and never registers a
 * listener, per this issue's "field left unset when unavailable without that permission".
 */
class TelephonyNetworkSignalStrengthSource(
    private val context: Context,
    private val telephonyManager: TelephonyManager,
) : SignalStrengthSource {
    override val signalLevel: Flow<Int?> =
        if (context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
            flowOf(null)
        } else {
            // TelephonyCallback (API 31+) takes an executor; PhoneStateListener needed a Looper thread and
            // crashed when collected on a background dispatcher.
            callbackFlow {
                val callback =
                    object : TelephonyCallback(), TelephonyCallback.SignalStrengthsListener {
                        override fun onSignalStrengthsChanged(signalStrength: SignalStrength) {
                            trySend(signalStrength.level)
                        }
                    }
                telephonyManager.registerTelephonyCallback(Runnable::run, callback)
                awaitClose { telephonyManager.unregisterTelephonyCallback(callback) }
            }
        }
}
