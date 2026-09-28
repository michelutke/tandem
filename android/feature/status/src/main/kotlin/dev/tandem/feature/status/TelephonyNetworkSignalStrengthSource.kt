package dev.tandem.feature.status

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.telephony.PhoneStateListener
import android.telephony.SignalStrength
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
@Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
class TelephonyNetworkSignalStrengthSource(
    private val context: Context,
    private val telephonyManager: TelephonyManager,
) : SignalStrengthSource {
    override val signalLevel: Flow<Int?> =
        if (context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
            flowOf(null)
        } else {
            callbackFlow {
                val listener =
                    object : PhoneStateListener() {
                        override fun onSignalStrengthsChanged(signalStrength: SignalStrength) {
                            trySend(signalStrength.level)
                        }
                    }
                telephonyManager.listen(listener, PhoneStateListener.LISTEN_SIGNAL_STRENGTHS)
                awaitClose { telephonyManager.listen(listener, PhoneStateListener.LISTEN_NONE) }
            }
        }
}
