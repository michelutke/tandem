package dev.tandem.core.transport.heartbeat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.PowerManager
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Doze/screen-state seam for the E20-15 unsolicited-heartbeat timer and dead-peer detector: [isIdle]
 * is `true` while the device is in Doze (`PowerManager.isDeviceIdleMode`), and [screenOn] fires once
 * per `ACTION_SCREEN_ON`. Production is [PowerManagerDeviceIdleSource]; tests use a plain
 * [MutableStateFlow]/[MutableSharedFlow] pair instead of a fake implementing this interface, mirroring
 * how [dev.tandem.core.transport.reconnect.NetworkMonitor] callers are tested.
 */
interface DeviceIdleSource {
    val isIdle: StateFlow<Boolean>
    val screenOn: Flow<Unit>
}

/**
 * Production [DeviceIdleSource] (E20-15): registers one [BroadcastReceiver] for
 * `ACTION_DEVICE_IDLE_MODE_CHANGED` and `ACTION_SCREEN_ON`. Tested under Robolectric (E00-20),
 * grabbing the registered receiver via `shadowOf(context).registeredReceivers` and invoking it
 * directly, mirroring `ConnectivityManagerNetworkMonitorTest`'s own
 * `shadowOf(connectivityManager).networkCallbacks` idiom for a registered callback.
 */
class PowerManagerDeviceIdleSource(
    private val context: Context,
    private val powerManager: PowerManager,
) : DeviceIdleSource {
    private val mutableIsIdle = MutableStateFlow(powerManager.isDeviceIdleMode)
    override val isIdle: StateFlow<Boolean> = mutableIsIdle.asStateFlow()

    private val mutableScreenOn = MutableSharedFlow<Unit>(extraBufferCapacity = SCREEN_ON_BUFFER_CAPACITY)
    override val screenOn: Flow<Unit> = mutableScreenOn.asSharedFlow()

    private val receiver =
        object : BroadcastReceiver() {
            override fun onReceive(
                receiverContext: Context,
                intent: Intent,
            ) {
                when (intent.action) {
                    PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> mutableIsIdle.value = powerManager.isDeviceIdleMode
                    Intent.ACTION_SCREEN_ON -> mutableScreenOn.tryEmit(Unit)
                }
            }
        }

    /** Registers [receiver]. Callers own this instance's lifetime and MUST call [stop] once done. */
    fun start() {
        val filter =
            IntentFilter().apply {
                addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
                addAction(Intent.ACTION_SCREEN_ON)
            }
        context.registerReceiver(receiver, filter)
    }

    /** Unregisters [receiver]. Safe to call more than once. */
    fun stop() {
        runCatching { context.unregisterReceiver(receiver) }
    }

    private companion object {
        const val SCREEN_ON_BUFFER_CAPACITY = 8
    }
}
