package dev.tandem.feature.clipboard

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.ui.TandemActivity
import dev.tandem.feature.clipboard.di.ClipboardDispatchers
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.security.MessageDigest

/**
 * E31-12: transparent capture activity started by [ClipboardTileService]. Android 10+ blocks
 * background clipboard reads, so the clip is read only once this window gains focus (E31-07's
 * foreground capture), sent via [ClipboardSender], and the activity finishes. An empty,
 * non-text or sensitive clip sends nothing, matching the passive capture path.
 *
 * Not exported: reached only via the explicit-component intent [ClipboardTileService] builds.
 */
class ClipboardCaptureActivity : TandemActivity() {
    var sessionProvider: (Context) -> TandemSession? = { LiveClipboardSession.current }
    internal var dispatcher: CoroutineDispatcher = ClipboardDispatchers.default
    var clipboardReaderProvider: (Context) -> ClipboardReader = { context -> AndroidClipboardReader(context) }

    internal var loopGuard: ClipboardLoopGuard = LiveClipboardSession.loopGuard

    private var captured = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captured = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            overrideActivityTransition(OVERRIDE_TRANSITION_OPEN, 0, 0)
            overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || captured) return
        captured = true

        val clip = clipboardReaderProvider(this).currentClip()?.takeUnless { it.sensitive }
        val session = clip?.let { sessionProvider(this) }
        val isAuto = intent.getBooleanExtra(EXTRA_AUTO_CAPTURE, false)
        val hash = clip?.text?.sha256()
        val isRepeat = isAuto && hash != null && hash.contentEquals(LiveClipboardAutoCapture.lastSentHash)
        val isEcho = isAuto && hash != null && !isRepeat && !loopGuard.shouldSend(hash)
        val skip = isEcho || isRepeat
        if (clip == null || session == null || skip) {
            finish()
            return
        }
        if (isAuto) LiveClipboardAutoCapture.lastSentHash = hash

        CoroutineScope(SupervisorJob() + dispatcher).launch {
            ClipboardSender.send(clip.text, session)
            finish()
        }
    }

    companion object {
        private const val EXTRA_AUTO_CAPTURE = "dev.tandem.feature.clipboard.AUTO_CAPTURE"

        /** The explicit-component intent [ClipboardCaptureService] starts; auto captures skip echoes of Mac clips. */
        fun autoCaptureIntent(context: Context): Intent =
            Intent(context, ClipboardCaptureActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
                .putExtra(EXTRA_AUTO_CAPTURE, true)
    }
}

private fun String.sha256(): ByteArray = MessageDigest.getInstance("SHA-256").digest(toByteArray(Charsets.UTF_8))
