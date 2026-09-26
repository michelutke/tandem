package dev.tandem.core.pairing

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.revoke.TrustRemover
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.revoke
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.time.Duration.Companion.seconds

/**
 * User-triggered unpair: deletes local trust first, then if a Ready session exists,
 * sends Revoke on CONTROL and closes the session (E14-12). Tested with [FakeTandemSession]
 * and injected Clock (E00-18).
 */
class UnpairAction(
    private val trustRemover: TrustRemover,
    private val purgeRegistry: PeerDataPurgeRegistry,
) {
    /**
     * Unpairs the peer identified by [peerFingerprint]. If [session] is non-null and in Ready state,
     * sends Revoke on CONTROL (bounded by 2s timeout) and closes. Purges peer data after trust delete.
     */
    suspend fun unpair(
        peerFingerprint: SpkiFingerprint,
        session: TandemSession?,
    ) {
        // Delete local trust first
        trustRemover.remove(peerFingerprint)

        // Send Revoke if we have a Ready session
        if (session != null && session.state.value is ConnectionState.Ready) {
            withTimeoutOrNull(2.seconds) {
                runCatching {
                    session.send(Channel.CHANNEL_CONTROL) { revoke = revoke {} }
                }
            }
            session.close()
        }

        // Purge peer data
        purgeRegistry.purgeAll(peerFingerprint)
    }
}
