package dev.tandem.app.service

import kotlinx.coroutines.flow.Flow

/**
 * Seam over "does a paired Mac exist" (E13-02 trust store), kept narrow so [ServiceStarter] and
 * [TandemService] stay plain unit-tested against a fake instead of depending on the Room-backed
 * `TrustStore` directly (CLAUDE.md's Robolectric rule; same idiom as core/pairing's
 * `TrustCommitter`). [TrustStorePairedPeerRepository] is the production implementation a higher
 * layer composes with the real trust store.
 */
fun interface PairedPeerRepository {
    /** Emits the current "at least one paired Mac exists" state, and again on every change. */
    fun observeHasPairedPeer(): Flow<Boolean>
}
