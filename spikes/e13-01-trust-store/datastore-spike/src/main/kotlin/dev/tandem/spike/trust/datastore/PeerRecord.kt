package dev.tandem.spike.trust.datastore

/** Plain-Kotlin mirror of the backlog E13-02 peer record shape, decoupled from the proto wire type. */
data class PeerRecord(
    val deviceId: String,
    val displayName: String,
    val spkiSha256Hex: String,
    val pairedAtEpochMs: Long,
    val lastSeenEpochMs: Long,
    val capabilities: List<String>,
    val pendingRotation: Boolean = false,
)
