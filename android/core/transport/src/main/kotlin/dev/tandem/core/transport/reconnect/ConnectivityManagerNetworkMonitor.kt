package dev.tandem.core.transport.reconnect

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/**
 * Production [NetworkMonitor] (E20-07): registers one default-network callback and emits on
 * every `onAvailable`/`onCapabilitiesChanged`, unregistering when the collector stops. Tested
 * under Robolectric (E00-20) rather than a real device, per this issue's own seam note.
 */
class ConnectivityManagerNetworkMonitor(
    private val connectivityManager: ConnectivityManager,
) : NetworkMonitor {
    override val available: Flow<Unit> =
        callbackFlow {
            val callback =
                object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        trySend(Unit)
                    }

                    override fun onCapabilitiesChanged(
                        network: Network,
                        networkCapabilities: NetworkCapabilities,
                    ) {
                        trySend(Unit)
                    }
                }
            connectivityManager.registerDefaultNetworkCallback(callback)
            awaitClose { connectivityManager.unregisterNetworkCallback(callback) }
        }
}
