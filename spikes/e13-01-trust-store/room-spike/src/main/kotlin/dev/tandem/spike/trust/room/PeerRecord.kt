package dev.tandem.spike.trust.room

/** Plain-Kotlin mirror of the backlog E13-02 peer record shape, decoupled from the Room entity. */
data class PeerRecord(
    val deviceId: String,
    val displayName: String,
    val spkiSha256Hex: String,
    val pairedAtEpochMs: Long,
    val lastSeenEpochMs: Long,
    val capabilities: List<String>,
)

internal fun PeerRecord.toEntity() = PeerRecordEntity(
    spkiSha256Hex = spkiSha256Hex,
    deviceId = deviceId,
    displayName = displayName,
    pairedAtEpochMs = pairedAtEpochMs,
    lastSeenEpochMs = lastSeenEpochMs,
    capabilitiesCsv = capabilities.joinToString(","),
)

internal fun PeerRecordEntity.toDomain() = PeerRecord(
    deviceId = deviceId,
    displayName = displayName,
    spkiSha256Hex = spkiSha256Hex,
    pairedAtEpochMs = pairedAtEpochMs,
    lastSeenEpochMs = lastSeenEpochMs,
    capabilities = if (capabilitiesCsv.isEmpty()) emptyList() else capabilitiesCsv.split(","),
)
