package dev.tandem.core.storage.trust

import dev.tandem.core.crypto.SpkiFingerprint
import java.time.Clock

/**
 * Updates peer records on Ready (E12-17): sets lastSeen = injected Clock now + negotiated
 * capabilities. Never creates records (invariant 3: updates only matching SPKI fingerprints).
 * Failed handshakes, failed hellos and pairing connections don't touch records (only
 * normal authenticated Ready state calls this).
 */
class PeerRecordUpdater(
    private val clock: Clock,
) {
    suspend fun updateOnReady(
        store: TrustStore,
        handshakeSPKI: SpkiFingerprint,
        capabilities: List<String>,
    ) {
        val existing = store.get(handshakeSPKI) ?: return
        val updated =
            existing.copy(
                lastSeenEpochMs = clock.instant().toEpochMilli(),
                capabilities = capabilities,
            )
        store.put(updated)
    }
}
