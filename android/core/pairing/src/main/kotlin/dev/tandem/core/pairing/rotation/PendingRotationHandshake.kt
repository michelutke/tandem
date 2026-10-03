package dev.tandem.core.pairing.rotation

import dev.tandem.core.crypto.ActiveIdentityAlias
import dev.tandem.core.crypto.IdentityKeyStore

/**
 * Recovers from a lost `RotationAck` (E70-08): if the Mac already committed the new key, a handshake
 * with the old key is rejected. While a rotation is pending (new key under
 * [ActiveIdentityAlias.nextAlias]), the handshake is retried once with the pending key; success
 * commits the rotation locally, failure restores the old key. Never generates a key.
 */
class PendingRotationHandshake(
    private val keyStore: IdentityKeyStore,
    private val activeAlias: ActiveIdentityAlias,
) {
    /** [handshake] connects with the key named by [ActiveIdentityAlias.current]; true when the peer accepted it. */
    suspend fun connect(handshake: suspend () -> Boolean): Boolean = handshake() || retryWithPendingKey(handshake)

    private suspend fun retryWithPendingKey(handshake: suspend () -> Boolean): Boolean {
        val oldAlias = activeAlias.current
        val pendingAlias = activeAlias.nextAlias()
        if (keyStore.get(pendingAlias) == null) return false
        activeAlias.activate(pendingAlias)
        val accepted = handshake()
        if (accepted) keyStore.delete(oldAlias) else activeAlias.activate(oldAlias)
        return accepted
    }
}
