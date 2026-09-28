package dev.tandem.feature.status

import android.content.Intent
import android.os.BatteryManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

/**
 * BatteryReceiverStatusSource test (E23-02), on Robolectric (E00-20): registers through the real
 * `Context.registerReceiver` call path (Robolectric's `ShadowApplication` intercepts it and hands
 * back the registered receiver for the test to invoke directly, since Robolectric has no built-in
 * "simulate battery change" trigger), mirroring `core:transport`'s
 * `ConnectivityManagerNetworkMonitorTest` (E20-07).
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class BatteryReceiverStatusSourceTest {
    // The system delivers ACTION_BATTERY_CHANGED as a genuinely external implicit broadcast
    // (detekt's ImplicitInternalIntent rule doc: suppress rather than add a meaningless
    // .setPackage(...) to an intent that must stay implicit to match what the platform sends).
    @Suppress("ImplicitInternalIntent")
    @Test
    fun batteryStatusSource_batteryChangedIntent_emitsLevelAndCharging() =
        runTest {
            val context = RuntimeEnvironment.getApplication()
            val source = BatteryReceiverStatusSource(context)

            val firstEvent = async { source.batteryStatus.first() }
            runCurrent() // lets callbackFlow's block run and register the receiver

            val receiver = shadowOf(context).registeredReceivers.last().broadcastReceiver
            val intent =
                Intent(Intent.ACTION_BATTERY_CHANGED).apply {
                    putExtra(BatteryManager.EXTRA_LEVEL, 60)
                    putExtra(BatteryManager.EXTRA_SCALE, 100)
                    putExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_CHARGING)
                }
            receiver.onReceive(context, intent)
            runCurrent()

            assertEquals(BatteryStatus(level = 60, isCharging = true), firstEvent.await())
        }
}
