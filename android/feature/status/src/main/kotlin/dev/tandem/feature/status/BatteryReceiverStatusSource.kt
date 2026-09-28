package dev.tandem.feature.status

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import androidx.core.content.ContextCompat
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/**
 * Production [BatteryStatusSource] (E23-02): registers an `ACTION_BATTERY_CHANGED` receiver and
 * emits the current level/charging state on every broadcast, unregistering when the collector
 * stops. Tested under Robolectric (E00-20) rather than a real device.
 */
class BatteryReceiverStatusSource(
    private val context: Context,
) : BatteryStatusSource {
    override val batteryStatus: Flow<BatteryStatus> =
        callbackFlow {
            val receiver =
                object : BroadcastReceiver() {
                    override fun onReceive(
                        context: Context,
                        intent: Intent,
                    ) {
                        trySend(intent.toBatteryStatus())
                    }
                }
            val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            ContextCompat.registerReceiver(context, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
            awaitClose { context.unregisterReceiver(receiver) }
        }

    private companion object {
        const val PERCENTAGE_SCALE = 100

        fun Intent.toBatteryStatus(): BatteryStatus {
            val level = getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            val percentage = if (level >= 0 && scale > 0) (level * PERCENTAGE_SCALE) / scale else 0
            val status = getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            val isCharging =
                status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
            return BatteryStatus(level = percentage, isCharging = isCharging)
        }
    }
}
