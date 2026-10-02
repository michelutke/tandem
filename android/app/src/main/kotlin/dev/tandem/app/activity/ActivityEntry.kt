package dev.tandem.app.activity

import java.time.Instant

enum class ActivityEventType(
    val label: String,
) {
    FileReceived("File received"),
    ClipboardFromMac("Clipboard from Mac"),
    Mirroring("Mirroring"),
    FindPhone("Find phone"),
}

/**
 * One Activity feed row (E20-18, invariant 7). Metadata only: no content, name or text fields
 * exist by design, so none can be stored or logged.
 */
data class ActivityEntry(
    val type: ActivityEventType,
    val sizeBytes: Long?,
    val durationSeconds: Long?,
    val timestamp: Instant,
)
