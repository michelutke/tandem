package dev.tandem.core.pairing

import dev.tandem.core.crypto.SpkiFingerprint

/**
 * Feature-local seam [UnpairAction] deletes through on [UnpairAction.unpair] (E14-12).
 * Kept small, without a storage dependency, so this module's tests stay plain JUnit5 with no
 * Room/`Context` dependency (CLAUDE.md's Robolectric rule); a higher layer composes this with
 * the real trust store (E13-02).
 */
fun interface TrustRemover {
    /** Deletes [fingerprint] from the local trust store. */
    suspend fun delete(fingerprint: SpkiFingerprint)
}
