package dev.tandem.feature.clipboard

import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context

/** A text clip read from the system clipboard, and whether its source flagged it sensitive. */
data class ClipboardClip(
    val text: String,
    val sensitive: Boolean,
)

/**
 * E31-07 seam over [ClipboardManager]: [MainActivity][dev.tandem.app.MainActivity]'s
 * foreground-capture (`onWindowFocusChanged`) and in-app "Send clipboard to Mac" button both read
 * the clipboard only through this interface, never `ClipboardManager` directly, so tests can
 * script a clip (or its absence) with a recording fake instead of a real system clipboard.
 */
fun interface ClipboardReader {
    /** The current clip's text and sensitivity, or `null` if there is no clip or it is not text. */
    fun currentClip(): ClipboardClip?
}

/**
 * Real [ClipboardReader] over the platform [ClipboardManager]. [EXTRA_IS_SENSITIVE] is only
 * readable on API 33+ (docs/planning/backlog/phase-3.yaml E31-07); below that this always reports
 * `sensitive = false`.
 */
class AndroidClipboardReader(
    private val context: Context,
) : ClipboardReader {
    override fun currentClip(): ClipboardClip? {
        val clipData = context.getSystemService(ClipboardManager::class.java)?.primaryClip
        val text =
            clipData
                ?.takeIf { it.itemCount > 0 }
                ?.getItemAt(0)
                ?.text
                ?.toString()
        return text?.let { ClipboardClip(it, sensitive = isSensitive(clipData.description)) }
    }

    private fun isSensitive(description: ClipDescription): Boolean =
        description.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE, false) ?: false
}
