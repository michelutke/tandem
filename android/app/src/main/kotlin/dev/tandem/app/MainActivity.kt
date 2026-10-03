package dev.tandem.app

import android.content.Context
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import dagger.hilt.android.AndroidEntryPoint
import dev.tandem.app.di.AppDispatchers
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.ui.TandemActivity
import dev.tandem.feature.clipboard.AndroidClipboardReader
import dev.tandem.feature.clipboard.ClipboardReader
import dev.tandem.feature.clipboard.ClipboardSender
import dev.tandem.feature.clipboard.LiveClipboardSession
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

// Launcher activity (E00-03): a blank screen proving the real `TandemApplication` Hilt component
// initializes on-device. Superseded by onboarding (F-4.1) once core/designsystem lands (E00-31).
//
// E31-07: also this app's foreground-capture and in-app "Send clipboard to Mac" button entry
// points (PRD F-6.2, UC-13), since it is currently the app's only screen.
//   - Foreground capture: whenever this Activity gains window focus, [onWindowFocusChanged] reads
//     the clipboard via [clipboardReaderProvider] and, if it holds text and is not sensitive,
//     sends it via [ClipboardSender]. The clipboard is read from no other place or callback, so a
//     background Tandem process never attempts a read outside this window
//     (docs/planning/backlog/phase-3.yaml E31-07 acceptance criterion 3).
//   - A sensitive clip (`ClipDescription.EXTRA_IS_SENSITIVE`, API 33+) is silently skipped on
//     window focus, but sent (with `sensitive = true`) when the user explicitly taps the button --
//     the user's explicit action is treated as intentional, unlike the passive focus-gained
//     capture.
//
// [sessionProvider]/[dispatcher]/[clipboardReaderProvider] are `internal var` seams, the same
// no-composition-root convention `ShareTargetActivity`/`ProcessTextActivity` (E31-06) use: nothing
// yet wires a live [TandemSession] into a feature entry point.
@AndroidEntryPoint
class MainActivity : TandemActivity() {
    internal var sessionProvider: (Context) -> TandemSession? = { LiveClipboardSession.current }
    internal var dispatcher: CoroutineDispatcher = AppDispatchers.default
    internal var clipboardReaderProvider: (Context) -> ClipboardReader = { context -> AndroidClipboardReader(context) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            Surface(modifier = Modifier.fillMaxSize()) {
                SendClipboardButton(onClick = ::onSendClipboardButtonTapped)
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) return

        val clip = clipboardReaderProvider(this).currentClip()
        if (clip != null && !clip.sensitive) sendClip(clip.text, sensitive = false)
    }

    internal fun onSendClipboardButtonTapped() {
        val clip = clipboardReaderProvider(this).currentClip() ?: return
        sendClip(clip.text, sensitive = clip.sensitive)
    }

    private fun sendClip(
        text: String,
        sensitive: Boolean,
    ) {
        val session = sessionProvider(this) ?: return
        CoroutineScope(SupervisorJob() + dispatcher).launch {
            ClipboardSender.send(text, session, sensitive = sensitive)
        }
    }
}

@Composable
private fun SendClipboardButton(onClick: () -> Unit) {
    Button(onClick = onClick) {
        Text("Send clipboard to Mac")
    }
}
