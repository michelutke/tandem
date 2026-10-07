package dev.tandem.feature.files

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.core.content.IntentCompat
import dev.tandem.core.ui.TandemActivity

/**
 * E40-11: "Send to Mac" share-sheet target for files (PRD F-7.3), declared in `:app`'s manifest with
 * `ACTION_SEND` / `ACTION_SEND_MULTIPLE` + `*` / `*` filters. No UI of its own: hands the
 * `EXTRA_STREAM` URIs to [SendEntry] and finishes. [starter] is a `var` seam, as
 * `ShareTargetActivity.sessionProvider` is: null falls back to [LiveFileSession].
 */
class ShareFilesActivity : TandemActivity() {
    var starter: TransferStarter? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        entry().offer(streams())
        finish()
    }

    private fun entry() =
        SendEntry(packageName, contentResolver, starter ?: SendFeedbackToasts.liveStarter(applicationContext))

    private fun streams(): List<Uri> =
        when (intent?.action) {
            Intent.ACTION_SEND -> {
                listOfNotNull(IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java))
            }

            Intent.ACTION_SEND_MULTIPLE -> {
                IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
            }

            else -> {
                emptyList()
            }
        }
}
