package dev.tandem.core.pairing

import dev.tandem.core.crypto.SpkiFingerprint

/**
 * Seam for purging peer-specific data when a peer is unpa paired (E14-12, Cycle 4).
 * Later stores (E40-05 transfer temp files) register implementations with [PeerDataPurgeRegistry],
 * and unpair runs every purger after the trust record is deleted.
 */
fun interface PeerDataPurging {
    /** Purges all data associated with [peerFingerprint]. */
    suspend fun purgeAll(peerFingerprint: SpkiFingerprint)
}
