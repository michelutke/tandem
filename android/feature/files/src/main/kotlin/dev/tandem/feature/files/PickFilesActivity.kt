package dev.tandem.feature.files

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
    var starter: TransferStarter = TransferStarter { }
    internal var registry: ActivityResultRegistry? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val picker =
            registerForActivityResult(
                ActivityResultContracts.OpenMultipleDocuments(),
                registry ?: activityResultRegistry,
            ) { uris ->
                SendEntry(packageName, contentResolver, starter).offer(uris)
                finish()
            }
        picker.launch(arrayOf("*/*"))
    }
}
