package dev.tandem.core.storage.trust

/**
 * Peer record persisted by the Android trust store (F-1.2, E13-02): `{deviceId, displayName,
 * spkiSha256, pairedAt, lastSeen, capabilities}`. [spkiSha256Base64Url] (the same encoding as the
 * QR `fp` param, SPEC.md §2, and [dev.tandem.core.crypto.SpkiFingerprint.base64Url]) is the only
 * lookup key (invariant 3, CLAUDE.md) -- [deviceId] is a display field, never a key.
 */
data class PeerRecord(
    val deviceId: String,
    val displayName: String,
    val spkiSha256Base64Url: String,
    val pairedAtEpochMs: Long,
    val lastSeenEpochMs: Long,
    val capabilities: List<String>,
)

internal fun PeerRecord.toEntity() =
    PeerRecordEntity(
        spkiSha256Base64Url = spkiSha256Base64Url,
        deviceId = deviceId,
        displayName = displayName,
        pairedAtEpochMs = pairedAtEpochMs,
        lastSeenEpochMs = lastSeenEpochMs,
        capabilitiesCsv = capabilities.joinToString(","),
    )

internal fun PeerRecordEntity.toDomain() =
    PeerRecord(
        deviceId = deviceId,
        displayName = displayName,
        spkiSha256Base64Url = spkiSha256Base64Url,
        pairedAtEpochMs = pairedAtEpochMs,
        lastSeenEpochMs = lastSeenEpochMs,
        capabilities = if (capabilitiesCsv.isEmpty()) emptyList() else capabilitiesCsv.split(","),
    )
