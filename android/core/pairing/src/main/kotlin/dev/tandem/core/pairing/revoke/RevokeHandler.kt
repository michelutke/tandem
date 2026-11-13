package dev.tandem.core.pairing.revoke

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.PeerDataPurgeRegistry
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.TandemSession

/** Removes a peer's trust record (bound to the storage trust store's `unpair` by the app). */
fun interface TrustRemover {
    suspend fun remove(fingerprint: SpkiFingerprint)
}

/**
 * Handles a Revoke received on a Ready session (E14-19): the peer's trust is deleted first, then
 * the session is closed, so no reconnect to that peer is possible, then the peer's data is purged
 * through [purgeRegistry], as for a user unpair. A Revoke before Ready (e.g. during a pairing
 * attempt) is ignored.
 */
class RevokeHandler(
    private val session: TandemSession,
    private val peerFingerprint: SpkiFingerprint,
    private val trustRemover: TrustRemover,
    private val purgeRegistry: PeerDataPurgeRegistry,
) {
    /** Returns true if the Revoke was applied. */
    suspend fun handleRevoke(): Boolean {
        if (session.state.value !is ConnectionState.Ready) return false
        trustRemover.remove(peerFingerprint)
        session.close()
        purgeRegistry.purgeAll(peerFingerprint)
        return true
    }
}
