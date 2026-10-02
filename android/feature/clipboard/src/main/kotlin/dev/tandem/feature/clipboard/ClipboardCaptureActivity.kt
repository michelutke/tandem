package dev.tandem.feature.clipboard

import android.content.Context
import android.os.Bundle
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.ui.TandemActivity
import dev.tandem.feature.clipboard.di.ClipboardDispatchers
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * E31-12: transparent capture activity started by [ClipboardTileService]. Android 10+ blocks
 * background clipboard reads, so the clip is read only once this window gains focus (E31-07's
 * foreground capture), sent via [ClipboardSender], and the activity finishes. An empty,
 * non-text or sensitive clip sends nothing, matching the passive capture path.
 *
 * Not exported: reached only via the explicit-component intent [ClipboardTileService] builds.
 */
class ClipboardCaptureActivity : TandemActivity() {
    var sessionProvider: (Context) -> TandemSession? = { null }
    internal var dispatcher: CoroutineDispatcher = ClipboardDispatchers.default
    var clipboardReaderProvider: (Context) -> ClipboardReader = { context -> AndroidClipboardReader(context) }

    private var captured = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captured = false
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || captured) return
        captured = true

        val clip = clipboardReaderProvider(this).currentClip()?.takeUnless { it.sensitive }
        val session = clip?.let { sessionProvider(this) }
        if (clip == null || session == null) {
            finish()
            return
        }

        CoroutineScope(SupervisorJob() + dispatcher).launch {
            ClipboardSender.send(clip.text, session)
            finish()
        }
    }
}
