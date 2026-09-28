package dev.tandem.core.transport.reconnect

import kotlinx.coroutines.flow.Flow

/**
 * A stream of "the network changed, might be worth retrying now" hints (E20-07). Carries no
 * network-type information yet -- [available] emits once per underlying platform callback with no
 * payload; E23-02 (network-type-aware UI) is expected to extend this interface if it needs more
 * than "something changed" when it lands.
 */
interface NetworkMonitor {
    val available: Flow<Unit>
}
