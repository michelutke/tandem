package dev.tandem.feature.clipboard

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.ui.TandemActivity
import dev.tandem.feature.clipboard.di.ClipboardDispatchers
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * E31-06: "Send to Mac" share-sheet target (PRD F-6.2/F-6.3, UC-13), declared in `:app`'s manifest
 * with an `ACTION_SEND` + `text/plain` intent filter. Reads `Intent.EXTRA_TEXT` and hands it to
 * [ClipboardSender]; file/stream sharing is a separate future issue (E40-11) and is not handled
 * here -- an `ACTION_SEND` intent missing `EXTRA_TEXT` sends nothing.
 *
 * No UI of its own: finishes immediately once the send (or the too-large rejection) completes.
 *
 * [sessionProvider]/[dispatcher]/[toast] are `internal var` seams, the no-composition-root
 * convention `RingStopActionReceiver`/`BootReceiver` already use in `:app`: the system constructs
 * this Activity via a no-arg constructor, and nothing yet wires a live [TandemSession] into a
 * feature entry point (the same gap `RingStopActionReceiver`'s kdoc flags). A test substitutes
 * [sessionProvider] with a `FakeTandemSession`-backed one and [dispatcher] with an
 * `UnconfinedTestDispatcher`.
 */
class ShareTargetActivity : TandemActivity() {
    internal var sessionProvider: (Context) -> TandemSession? = { null }
    internal var dispatcher: CoroutineDispatcher = ClipboardDispatchers.default
    internal var toast: (Context, String) -> Unit = { context, message ->
        Toast.makeText(context, message, Toast.LENGTH_LONG).show()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val text = extractText()
        val session = text?.let { sessionProvider(this) }
        if (text == null || session == null) {
            finish()
            return
        }

        CoroutineScope(SupervisorJob() + dispatcher).launch {
            ClipboardSender.send(text, session) { toast(this@ShareTargetActivity, ClipboardSender.TOO_LARGE_TOAST) }
            finish()
        }
    }

    private fun extractText(): String? {
        if (intent?.action != Intent.ACTION_SEND || intent?.type != "text/plain") return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)
    }
}
