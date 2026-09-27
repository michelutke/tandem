package dev.tandem.core.pairing

import dev.tandem.core.crypto.SpkiFingerprint

/**
 * Registry for [PeerDataPurging] implementations, called by [UnpairAction] after deleting
 * the peer's trust record (E14-12, Cycle 4).
 */
class PeerDataPurgeRegistry {
    private val purgers = mutableListOf<PeerDataPurging>()

    fun register(purger: PeerDataPurging) {
        purgers += purger
    }

    suspend fun purgeAll(peerFingerprint: SpkiFingerprint) {
        for (purger in purgers) {
            runCatching { purger.purgeAll(peerFingerprint) }
        }
    }
}
