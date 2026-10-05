package dev.tandem.core.pairing.rotation

import dev.tandem.core.crypto.ActiveIdentityAlias
import dev.tandem.core.crypto.IdentityKeyStore
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

sealed interface HandshakeResult {
    /** The peer rejected the presented certificate (TLS alert / pin rejection). */
    data object Rejected : HandshakeResult

    /** Connectivity failure; says nothing about the key. */
    data object NetworkError : HandshakeResult

    /** TLS completed; [authenticated] only when the session reached Ready with the peer pinned. */
    data class Accepted(
        val authenticated: Boolean,
    ) : HandshakeResult
}

/**
 * Recovers from a lost `RotationAck` (E70-08): if the Mac already committed the new key, a handshake
 * with the old key is rejected. While a rotation is pending (new key under
 * [ActiveIdentityAlias.nextAlias]), the handshake is retried once with the pending key, only after a
 * [HandshakeResult.Rejected]. Only an authenticated acceptance commits the rotation: the alias is
 * persisted and the old key deleted; until then the old alias stays the persisted active identity.
 * Never generates a key.
 */
class PendingRotationHandshake(
    private val keyStore: IdentityKeyStore,
    private val activeAlias: ActiveIdentityAlias,
    private val rotationLock: Mutex,
) {
    /**
     * [handshake] connects with the key stored under the alias it is given. True when authenticated.
     * Holds the shared rotation lock throughout, so [handshake] must never await a rotation.
     */
    suspend fun connect(handshake: suspend (alias: String) -> HandshakeResult): Boolean =
        rotationLock.withLock {
            val oldAlias = activeAlias.current
            when (val first = handshake(oldAlias)) {
                HandshakeResult.Rejected -> retryWithPendingKey(oldAlias, handshake)
                HandshakeResult.NetworkError -> false
                is HandshakeResult.Accepted -> first.authenticated
            }
        }

    private suspend fun retryWithPendingKey(
        oldAlias: String,
        handshake: suspend (alias: String) -> HandshakeResult,
    ): Boolean {
        val pendingAlias = activeAlias.nextAlias()
        if (keyStore.get(pendingAlias) == null) return false
        val result = handshake(pendingAlias)
        val committed = result is HandshakeResult.Accepted && result.authenticated
        if (committed) {
            activeAlias.activate(pendingAlias)
            keyStore.delete(oldAlias)
        }
        return committed
    }
}
