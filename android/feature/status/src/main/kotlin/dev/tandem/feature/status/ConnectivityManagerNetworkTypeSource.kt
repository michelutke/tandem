package dev.tandem.feature.status

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import dev.tandem.protocol.v1.NetworkType
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/**
 * Production [NetworkTypeSource] (E23-02): registers one default-network callback and classifies
 * `onCapabilitiesChanged`/`onLost` into [NetworkType] (Wi-Fi / cellular / offline), unregistering
 * when the collector stops. Tested under Robolectric (E00-20) rather than a real device, mirroring
 * `core:transport`'s `ConnectivityManagerNetworkMonitor` (E20-07).
 */
class ConnectivityManagerNetworkTypeSource(
    private val connectivityManager: ConnectivityManager,
) : NetworkTypeSource {
    override val networkType: Flow<NetworkType> =
        callbackFlow {
            val callback =
                object : ConnectivityManager.NetworkCallback() {
                    override fun onCapabilitiesChanged(
                        network: Network,
                        networkCapabilities: NetworkCapabilities,
                    ) {
                        trySend(networkCapabilities.toNetworkType())
                    }

                    override fun onLost(network: Network) {
                        trySend(NetworkType.NETWORK_TYPE_OFFLINE)
                    }
                }
            connectivityManager.registerDefaultNetworkCallback(callback)
            awaitClose { connectivityManager.unregisterNetworkCallback(callback) }
        }

    private companion object {
        fun NetworkCapabilities.toNetworkType(): NetworkType =
            when {
                hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> NetworkType.NETWORK_TYPE_WIFI
                hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> NetworkType.NETWORK_TYPE_CELLULAR
                else -> NetworkType.NETWORK_TYPE_OFFLINE
            }
    }
}
