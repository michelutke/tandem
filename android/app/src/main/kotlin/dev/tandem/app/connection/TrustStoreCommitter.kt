package dev.tandem.app.connection

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.TrustCommitter
import dev.tandem.core.storage.trust.PeerRecord
import java.time.Instant

/**
 * Production [TrustCommitter] (E20-26): pins the Mac by SPKI fingerprint only (invariant 3). The
 * record's `deviceId` is a display field, never a lookup key, so it carries the fingerprint too.
 * [put] is `TrustStore::put`.
 */
class TrustStoreCommitter(
    private val put: suspend (PeerRecord) -> Unit,
) : TrustCommitter {
    override suspend fun commit(
        fingerprint: SpkiFingerprint,
        macName: String,
        pairedAt: Instant,
    ) {
        put(
            PeerRecord(
                deviceId = fingerprint.base64Url,
                displayName = macName,
                spkiSha256Base64Url = fingerprint.base64Url,
                pairedAtEpochMs = pairedAt.toEpochMilli(),
                lastSeenEpochMs = pairedAt.toEpochMilli(),
                capabilities = emptyList(),
            ),
        )
    }
}
