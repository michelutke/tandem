package dev.tandem.core.transport.reconnect

import android.content.Context
import android.net.ConnectivityManager
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
import org.robolectric.shadows.ShadowNetwork

/**
 * ConnectivityManagerNetworkMonitor test (E20-07), on Robolectric (E00-20): registers through the
 * real `ConnectivityManager.registerDefaultNetworkCallback` call path (Robolectric's
 * `ShadowConnectivityManager` intercepts it and hands back the registered callback for the test
 * to invoke directly, since Robolectric has no built-in "simulate connectivity change" trigger).
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class ConnectivityManagerNetworkMonitorTest {
    @Test
    fun connectivityManagerNetworkMonitor_defaultNetworkCallbackFires_emitsAvailable() =
        runTest {
            val context = RuntimeEnvironment.getApplication()
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val shadow = shadowOf(connectivityManager)
            val monitor = ConnectivityManagerNetworkMonitor(connectivityManager)

            val firstEvent = async { monitor.available.first() }
            runCurrent() // lets callbackFlow's block run and register the callback

            val callback = shadow.networkCallbacks.single()
            callback.onAvailable(ShadowNetwork.newInstance(NET_ID))
            runCurrent()

            assertEquals(Unit, firstEvent.await())
        }

    private companion object {
        const val NET_ID = 1
    }
}
