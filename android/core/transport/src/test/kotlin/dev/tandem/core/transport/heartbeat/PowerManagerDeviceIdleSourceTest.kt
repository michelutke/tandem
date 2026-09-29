package dev.tandem.core.transport.heartbeat

import android.content.Context
import android.content.Intent
import android.os.PowerManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

/**
 * [PowerManagerDeviceIdleSource] test (E20-15), on Robolectric (E00-20): registers through the real
 * `Context.registerReceiver` call path, then grabs the registered [android.content.BroadcastReceiver]
 * back off the shadow context and invokes it directly with the real Doze broadcast action --
 * Robolectric has no built-in "simulate Doze" trigger, mirroring
 * `ConnectivityManagerNetworkMonitorTest`'s identical `shadowOf(...).<callbacks>.single()` idiom for
 * a registered callback.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class PowerManagerDeviceIdleSourceTest {
    @Test
    fun deviceIdleSource_idleModeChangedBroadcast_emitsNewIdleState() =
        runTest {
            val context = RuntimeEnvironment.getApplication()
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            shadowOf(powerManager).setIsDeviceIdleMode(false)
            val source = PowerManagerDeviceIdleSource(context, powerManager)
            source.start()

            shadowOf(powerManager).setIsDeviceIdleMode(true)
            val registeredReceivers = shadowOf(context).registeredReceivers
            val registration =
                registeredReceivers.single { it.intentFilter.hasAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED) }
            val intent = Intent(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED).setPackage(context.packageName)
            registration.broadcastReceiver.onReceive(context, intent)

            assertTrue(source.isIdle.value)
            source.stop()
        }
}
