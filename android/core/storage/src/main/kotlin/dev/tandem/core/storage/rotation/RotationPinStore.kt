package dev.tandem.core.storage.rotation

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.storage.trust.PeerRecord

/** Which of a peer record's pins a fingerprint matched (SPEC.md #key-rotation, Grace pin). */
enum class PinKind { PRIMARY, GRACE, PENDING }

data class ResolvedPin(
    val kind: PinKind,
    val record: PeerRecord,
)

/**
 * Trust-store operations the rotation receiver needs (E70-04). Every mutation is atomic: an
 * interrupted call leaves the record in its old or its new state, never partially updated.
 */
interface RotationPinStore {
    /** Matches the primary pin, an unexpired grace pin or an unexpired pending pin. */
    suspend fun resolve(
        fingerprint: SpkiFingerprint,
        nowEpochMs: Long,
    ): ResolvedPin?

    /** True if [fingerprint] is any record's primary pin or unexpired grace pin. */
    suspend fun isPrimaryOrGrace(
        fingerprint: SpkiFingerprint,
        nowEpochMs: Long,
    ): Boolean

    /** Stores [pending] on the record whose primary pin is [primary]; false if there is none. */
    suspend fun setPending(
        primary: SpkiFingerprint,
        pending: SpkiFingerprint,
        sinceEpochMs: Long,
    ): Boolean

    /** Makes the pending pin primary and the old primary a grace pin until [graceExpiresAtEpochMs]. */
    suspend fun promotePending(
        pending: SpkiFingerprint,
        graceExpiresAtEpochMs: Long,
    ): Boolean

    /** Purges the grace pin of the record whose primary pin is [primary]. */
    suspend fun clearGrace(primary: SpkiFingerprint)
}
