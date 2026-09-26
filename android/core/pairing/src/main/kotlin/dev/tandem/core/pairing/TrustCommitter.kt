package dev.tandem.core.pairing

import dev.tandem.core.crypto.SpkiFingerprint
import java.time.Instant

/**
 * Feature-local seam [PairingStateMachine] commits through on [PairingState.Paired] (E14-05;
 * SPEC.md §2 "Mutual confirmation": "the phone MUST commit the Mac's SPKI pin only after both (a)
 * `PairAccepted` has been received and (b) the owner taps 'Codes match'"). Kept this small,
 * rather than depending on the trust store (E13-02) directly, so this module's tests stay plain
 * JUnit5 with no Room/`Context` dependency (CLAUDE.md's Robolectric rule); a higher layer composes
 * this with the real trust store, which needs [pairedAt] (E14-05's injected `Clock`) for its
 * `pairedAt`/`lastSeen` fields.
 */
fun interface TrustCommitter {
    /** Commits [fingerprint] as the paired Mac's pin, with [macName] as its display name. */
    suspend fun commit(
        fingerprint: SpkiFingerprint,
        macName: String,
        pairedAt: Instant,
    )
}
