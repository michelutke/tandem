package dev.tandem.app.activity

import androidx.annotation.StringRes
import dev.tandem.app.R
import java.time.Instant

enum class ActivityEventType(
    @StringRes val label: Int,
) {
    FileReceived(R.string.activity_event_file_received),
    ClipboardFromMac(R.string.activity_event_clipboard_from_mac),
    Mirroring(R.string.activity_event_mirroring),
    FindPhone(R.string.activity_event_find_phone),
    PhoneCall(R.string.activity_event_phone_call),
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
