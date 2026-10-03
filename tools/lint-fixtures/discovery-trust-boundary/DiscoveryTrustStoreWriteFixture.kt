package dev.tandem.core.discovery

import dev.tandem.core.storage.trust.PeerRecord
import dev.tandem.core.storage.trust.TrustStore

// E21-06 fixture (permanent): proves DiscoveryTrustBoundary fires when the discovery module marks
// a peer trusted by writing the trust store instead of leaving the pin check to the handshake.
internal suspend fun markDiscoveredPeerTrusted(
    trustStore: TrustStore,
    record: PeerRecord,
) {
    trustStore.put(record)
}
