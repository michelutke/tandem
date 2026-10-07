package dev.tandem.core.discovery

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow

/**
 * [ServiceDiscovery] that browses only while local network access is granted. Without it the
 * platform answers NsdManager use with a blocking device-picker dialog, so [browse] emits nothing
 * and never touches [delegate]; callers fall back to the addresses stored at pairing.
 */
class PermissionGatedServiceDiscovery(
    private val delegate: ServiceDiscovery,
    private val hasLocalNetworkAccess: () -> Boolean,
) : ServiceDiscovery {
    override fun browse(): Flow<DiscoveryEvent> =
        flow {
            if (hasLocalNetworkAccess()) emitAll(delegate.browse())
        }
}
