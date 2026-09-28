package dev.tandem.feature.status

import dev.tandem.protocol.v1.NetworkType
import kotlinx.coroutines.flow.Flow

/**
 * A stream of the phone's current network connectivity (E23-02), fed into [StatusAggregator].
 *
 * `core:transport`'s `NetworkMonitor` (E20-07) exists to kick reconnect attempts and deliberately
 * carries no type information (its own doc comment: "no network-type information yet"), so it
 * cannot alone satisfy this issue's "Wi-Fi to cellular emits network type cellular" acceptance
 * criterion. This is a separate, feature-local seam over the same `ConnectivityManager` default-
 * network callback, but classifying the resulting capabilities into [NetworkType] instead of
 * emitting a bare change signal.
 */
interface NetworkTypeSource {
    val networkType: Flow<NetworkType>
}
