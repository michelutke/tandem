package dev.tandem.core.storage.trust

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Room mirror of [PeerRecord], keyed by [spkiSha256Base64Url] only (invariant 3, CLAUDE.md).
 * `capabilities` is stored comma-joined -- sufficient at this scale (single-digit to low-tens of
 * paired devices, E13-01 spike Finding 4); a Room `TypeConverter` would be equivalent.
 */
@Entity(tableName = "peer_record")
internal data class PeerRecordEntity(
    @PrimaryKey val spkiSha256Base64Url: String,
    val deviceId: String,
    val displayName: String,
    val pairedAtEpochMs: Long,
    val lastSeenEpochMs: Long,
    val capabilitiesCsv: String,
    val graceSpkiSha256Base64Url: String? = null,
    val graceExpiresAtEpochMs: Long? = null,
    val pendingSpkiSha256Base64Url: String? = null,
    val pendingSinceEpochMs: Long? = null,
)
