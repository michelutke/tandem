package dev.tandem.app.clipboard

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.os.Build
import android.os.PersistableBundle
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.ClipboardText
import kotlinx.coroutines.flow.collect

/**
 * Writes an incoming `ClipboardText` (E31-01) to the system clipboard (E31-05; PRD F-6.1,
 * UC-12). [start] collects `Channel.CHANNEL_CLIPBOARD` frames from a [TandemSession] until its
 * flow completes or the caller cancels, writing each one via [write].
 *
 * A sensitive clip additionally sets `ClipDescription.EXTRA_IS_SENSITIVE` so the system
 * suppresses its clipboard preview -- Android 13+/API 33 only, since the extra does not exist
 * below that (the physical-device preview check itself is the E00-23 manual gate, out of scope
 * here). Below API 33 a sensitive clip is written the same as any other, without the extra and
 * without error.
 *
 * Depends on the concrete `android.content.ClipboardManager` rather than a seam: this class is
 * already Robolectric-only per CLAUDE.md's Robolectric rule because `ClipboardManager` -- a final
 * framework class -- is itself the unavoidable Android type.
 */
class ClipboardWriter(
    private val clipboardManager: ClipboardManager,
) {
    suspend fun start(session: TandemSession) {
        session.receive(Channel.CHANNEL_CLIPBOARD).collect { envelope ->
            write(envelope.clipboardText)
        }
    }

    fun write(clipboardText: ClipboardText) {
        val clip = ClipData.newPlainText(CLIP_LABEL, clipboardText.text)
        if (clipboardText.sensitive && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            clip.description.extras =
                PersistableBundle().apply {
                    putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                }
        }
        clipboardManager.setPrimaryClip(clip)
    }

    private companion object {
        const val CLIP_LABEL = "Tandem"
    }
}
