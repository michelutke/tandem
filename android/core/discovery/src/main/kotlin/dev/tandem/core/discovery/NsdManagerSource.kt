package dev.tandem.core.discovery

import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * The only place this module calls into `android.net.nsd.NsdManager` (E21-04). Never registers a
 * service: only `discoverServices`/`resolveService`, whose mDNS traffic is handled by the system's
 * own daemon, never a socket this app opens or listens on (invariant 4) — advertising `_tandem._tcp`
 * is the Mac's job (E21-02), not this app's.
 */
class NsdManagerSource(
    private val nsdManager: NsdManager,
) : NsdSource {
    override fun browse(serviceType: String): Flow<NsdBrowseEvent> =
        callbackFlow {
            val listener =
                object : NsdManager.DiscoveryListener {
                    override fun onDiscoveryStarted(regType: String) = Unit

                    override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                        trySend(NsdBrowseEvent.ServiceFound(serviceInfo.toRef()))
                    }

                    override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                        trySend(NsdBrowseEvent.ServiceLost(serviceInfo.toRef()))
                    }

                    override fun onStartDiscoveryFailed(
                        regType: String,
                        errorCode: Int,
                    ) {
                        close()
                    }

                    override fun onStopDiscoveryFailed(
                        regType: String,
                        errorCode: Int,
                    ) = Unit

                    override fun onDiscoveryStopped(regType: String) = Unit
                }
            nsdManager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, listener)
            awaitClose { runCatching { nsdManager.stopServiceDiscovery(listener) } }
        }

    @Suppress("DEPRECATION")
    override suspend fun resolve(service: NsdServiceRef): ResolveOutcome =
        suspendCancellableCoroutine { continuation ->
            val info =
                NsdServiceInfo().apply {
                    serviceName = service.name
                    serviceType = service.serviceType
                }
            val listener =
                object : NsdManager.ResolveListener {
                    override fun onResolveFailed(
                        serviceInfo: NsdServiceInfo,
                        errorCode: Int,
                    ) {
                        val transient = errorCode == NsdManager.FAILURE_ALREADY_ACTIVE
                        continuation.resume(ResolveOutcome.Failure(transient))
                    }

                    override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                        continuation.resume(
                            ResolveOutcome.Success(
                                host = serviceInfo.host?.hostAddress.orEmpty(),
                                port = serviceInfo.port,
                                txtRecords = serviceInfo.attributesToMap(),
                            ),
                        )
                    }
                }
            nsdManager.resolveService(info, listener)
        }

    private fun NsdServiceInfo.toRef() = NsdServiceRef(name = serviceName, serviceType = serviceType)

    private fun NsdServiceInfo.attributesToMap(): Map<String, String> =
        attributes.mapValues { (_, value) -> value?.toString(Charsets.UTF_8).orEmpty() }
}
