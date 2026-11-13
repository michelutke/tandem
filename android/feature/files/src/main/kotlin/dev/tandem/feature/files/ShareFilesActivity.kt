package dev.tandem.feature.files

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.core.content.IntentCompat
import dev.tandem.core.ui.TandemActivity
import java.util.concurrent.Executor

/**
 * E40-11: "Send to Mac" share-sheet target for files (PRD F-7.3), declared in `:app`'s manifest with
 * `ACTION_SEND` / `ACTION_SEND_MULTIPLE` + `*` / `*` filters. No UI of its own: hands the
 * `EXTRA_STREAM` URIs to [SendEntry] on a background [executor] (provider queries and the staging
 * copy must not block the main thread) and finishes once that is done. [starter] is a `var` seam, as
 * `ShareTargetActivity.sessionProvider` is: null falls back to [LiveFileSession].
 */
class ShareFilesActivity : TandemActivity() {
    var starter: TransferStarter? = null
    internal var executor: Executor = SendEntry.BACKGROUND
    internal var onStagingFailed: (() -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val entry = entry()
        val uris = streams()
        // Stays alive until every stream is staged: the share-sheet read grant ends with this activity.
        executor.execute {
            try {
                entry.offer(uris)
            } finally {
                runOnUiThread { finish() }
            }
        }
    }

    private fun entry(): SendEntry {
        val staging = ShareStaging.inCache(cacheDir)
        return SendEntry(
            packageName,
            applicationContext.contentResolver,
            starter ?: SendFeedbackToasts.liveStarter(applicationContext) { staging.delete(it) },
            staging,
            onStagingFailed ?: { SendFeedbackToasts.show(applicationContext, SendFeedback.FAILED) },
        )
    }

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
