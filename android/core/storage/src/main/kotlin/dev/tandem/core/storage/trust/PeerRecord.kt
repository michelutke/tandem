package dev.tandem.core.storage.trust

/**
 * Peer record persisted by the Android trust store (F-1.2, E13-02): `{deviceId, displayName,
 * spkiSha256, pairedAt, lastSeen, capabilities}`. [spkiSha256Base64Url] (the same encoding as the
 * QR `fp` param, SPEC.md §2, and [dev.tandem.core.crypto.SpkiFingerprint.base64Url]) is the only
 * lookup key (invariant 3, CLAUDE.md) -- [deviceId] is a display field, never a key.
 *
 * Key rotation (E70-04, SPEC.md #key-rotation): [graceSpkiSha256Base64Url]/[graceExpiresAtEpochMs] is the
 * previous primary pin, accepted grace-only until purged; [pendingSpkiSha256Base64Url]/[pendingSinceEpochMs]
 * is a rotated Mac key not yet presented by a handshake. All four are null outside a rotation.
 */
data class PeerRecord(
    val deviceId: String,
    val displayName: String,
    val spkiSha256Base64Url: String,
    val pairedAtEpochMs: Long,
    val lastSeenEpochMs: Long,
    val capabilities: List<String>,
    val graceSpkiSha256Base64Url: String? = null,
    val graceExpiresAtEpochMs: Long? = null,
    val pendingSpkiSha256Base64Url: String? = null,
    val pendingSinceEpochMs: Long? = null,
)

internal fun PeerRecord.toEntity() =
    PeerRecordEntity(
        spkiSha256Base64Url = spkiSha256Base64Url,
        deviceId = deviceId,
        displayName = displayName,
        pairedAtEpochMs = pairedAtEpochMs,
        lastSeenEpochMs = lastSeenEpochMs,
        capabilitiesCsv = capabilities.joinToString(","),
        graceSpkiSha256Base64Url = graceSpkiSha256Base64Url,
        graceExpiresAtEpochMs = graceExpiresAtEpochMs,
        pendingSpkiSha256Base64Url = pendingSpkiSha256Base64Url,
        pendingSinceEpochMs = pendingSinceEpochMs,
    )

internal fun PeerRecordEntity.toDomain() =
    PeerRecord(
        deviceId = deviceId,
        displayName = displayName,
        spkiSha256Base64Url = spkiSha256Base64Url,
        pairedAtEpochMs = pairedAtEpochMs,
        lastSeenEpochMs = lastSeenEpochMs,
        capabilities = if (capabilitiesCsv.isEmpty()) emptyList() else capabilitiesCsv.split(","),
        graceSpkiSha256Base64Url = graceSpkiSha256Base64Url,
        graceExpiresAtEpochMs = graceExpiresAtEpochMs,
        pendingSpkiSha256Base64Url = pendingSpkiSha256Base64Url,
        pendingSinceEpochMs = pendingSinceEpochMs,
    )
