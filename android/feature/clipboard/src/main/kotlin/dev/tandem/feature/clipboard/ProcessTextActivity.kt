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
 * E31-06: `PROCESS_TEXT` entry point for selected text (PRD F-6.2/F-6.3, UC-13), declared in
 * `:app`'s manifest with an `ACTION_PROCESS_TEXT` + `text/plain` intent filter. Reads
 * `Intent.EXTRA_PROCESS_TEXT` as a `CharSequence` only -- read via `Bundle.get` and an `as?`
 * safe-cast, never `getCharSequenceExtra` (which throws `ClassCastException` on a differently-typed
 * extra) -- and ignores `Intent.EXTRA_PROCESS_TEXT_READONLY` entirely; a missing or non-`CharSequence`
 * `EXTRA_PROCESS_TEXT` sends nothing.
 *
 * See [ShareTargetActivity]'s kdoc for the no-UI / seam conventions this class shares with it.
 */
class ProcessTextActivity : TandemActivity() {
    var sessionProvider: (Context) -> TandemSession? = { LiveClipboardSession.current }
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
            ClipboardSender.send(text, session) { toast(this@ProcessTextActivity, ClipboardSender.TOO_LARGE_TOAST) }
            finish()
        }
    }

    private fun extractText(): String? {
        if (intent?.action != Intent.ACTION_PROCESS_TEXT) return null
        return (intent.extras?.get(Intent.EXTRA_PROCESS_TEXT) as? CharSequence)?.toString()
    }
}
