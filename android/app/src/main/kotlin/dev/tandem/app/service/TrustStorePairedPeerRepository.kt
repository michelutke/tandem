package dev.tandem.app.service

import dev.tandem.core.storage.trust.TrustStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Production [PairedPeerRepository] over the real trust store (E13-02). */
class TrustStorePairedPeerRepository(
    private val trustStore: TrustStore,
) : PairedPeerRepository {
    override fun observeHasPairedPeer(): Flow<Boolean> = trustStore.observeList().map { it.isNotEmpty() }
}
