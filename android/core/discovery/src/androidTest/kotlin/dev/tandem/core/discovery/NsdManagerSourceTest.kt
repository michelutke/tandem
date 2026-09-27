package dev.tandem.core.discovery

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.time.Duration.Companion.seconds

/**
 * E21-04 instrumented tdd: nsdManager_selfRegisteredTandemService_resolvedWithTxt. Registers a
 * `_tandem._tcp` test service against the real system `NsdManager` -- only test sources are exempt
 * from the `NoListenerSockets` detekt rule's `registerService` ban (invariant 4: the app's own main
 * sources never advertise; that is the Mac's job, E21-02) -- and asserts [NsdManagerSource] plus
 * [NsdServiceDiscovery] resolve it back with the same host/port/TXT. The real cross-device gate is
 * `docs/testing/manual-gates.md`'s `nsdBrowse_realMacSameWifi_resolvedWithin3s`.
 */
@RunWith(AndroidJUnit4::class)
class NsdManagerSourceTest {
    private val nsdManager =
        InstrumentationRegistry
            .getInstrumentation()
            .targetContext
            .getSystemService(Context.NSD_SERVICE) as NsdManager

    @Test
    fun nsdManager_selfRegisteredTandemService_resolvedWithTxt() =
        runBlocking(Dispatchers.IO) {
            val serviceName = "tandem-test-${System.nanoTime()}"
            val txt = mapOf("v" to "1", "id" to "0011223344556677")
            val listener = registerService(serviceName, txt)
            try {
                val discovery = NsdServiceDiscovery(NsdManagerSource(nsdManager), Dispatchers.IO)

                val resolved =
                    withTimeout(10.seconds) {
                        discovery
                            .browse()
                            .filterIsInstance<DiscoveryEvent.Resolved>()
                            .map { it.candidate }
                            .first { it.serviceName == serviceName }
                    }

                assertEquals(txt, resolved.txtRecords)
                assertTrue(resolved.port > 0)
            } finally {
                runCatching { nsdManager.unregisterService(listener) }
            }
        }

    private suspend fun registerService(
        name: String,
        txt: Map<String, String>,
    ): NsdManager.RegistrationListener =
        suspendCancellableCoroutine { continuation ->
            val info =
                NsdServiceInfo().apply {
                    serviceName = name
                    serviceType = NsdServiceDiscovery.SERVICE_TYPE
                    port = 12345
                    txt.forEach { (key, value) -> setAttribute(key, value) }
                }
            lateinit var listener: NsdManager.RegistrationListener
            listener =
                object : NsdManager.RegistrationListener {
                    override fun onRegistrationFailed(
                        serviceInfo: NsdServiceInfo,
                        errorCode: Int,
                    ) {
                        continuation.resumeWithException(IllegalStateException("registerService failed: $errorCode"))
                    }

                    override fun onUnregistrationFailed(
                        serviceInfo: NsdServiceInfo,
                        errorCode: Int,
                    ) = Unit

                    override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
                        continuation.resume(listener)
                    }

                    override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) = Unit
                }
            nsdManager.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener)
        }
}
