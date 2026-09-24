package dev.tandem.spike.trust.room

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Room mirror of the backlog E13-02 peer record shape, keyed by [spkiSha256Hex] only
 * (invariant 3 -- CLAUDE.md); deviceId is a display field, never a key.
 * `capabilities` is stored comma-joined -- a real implementation would use a Room TypeConverter
 * (out of scope for this spike, which only compares the persistence layer itself).
 */
@Entity(tableName = "peer_record")
data class PeerRecordEntity(
    @PrimaryKey val spkiSha256Hex: String,
    val deviceId: String,
    val displayName: String,
    val pairedAtEpochMs: Long,
    val lastSeenEpochMs: Long,
    val capabilitiesCsv: String,
)
