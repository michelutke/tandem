package dev.tandem.feature.files

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.contract.ActivityResultContracts
import dev.tandem.core.ui.TandemActivity

/**
 * E40-11: in-app Storage Access Framework entry point (PRD F-7.3). Not exported; launches
 * `OpenMultipleDocuments` and hands the picked URIs to [SendEntry]. A cancelled picker returns an
 * empty list and sends nothing. [registry] and [starter] are seams (see [ShareFilesActivity]).
 */
class PickFilesActivity : TandemActivity() {
    var starter: TransferStarter? = null
    internal var registry: ActivityResultRegistry? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val picker =
            registerForActivityResult(
                ActivityResultContracts.OpenMultipleDocuments(),
                registry ?: activityResultRegistry,
            ) { uris ->
                uris.forEach(::keepReadAccess)
                if (!entry().offer(uris)) uris.forEach(::releaseReadAccess)
                finish()
            }
        picker.launch(arrayOf("*/*"))
    }

    // The picker's grant ends with this activity, but bytes are read only after the Mac accepts;
    // the persisted grant is released once the transfer ends.
    private fun keepReadAccess(uri: Uri) {
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: SecurityException) {
            Unit
        }
    }

    private fun releaseReadAccess(uri: Uri) {
        try {
            applicationContext.contentResolver
                .releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: SecurityException) {
            Unit
        }
    }

    private fun entry() =
        SendEntry(
            packageName,
            contentResolver,
            starter ?: SendFeedbackToasts.liveStarter(applicationContext) { releaseReadAccess(Uri.parse(it.uri)) },
        )
}
