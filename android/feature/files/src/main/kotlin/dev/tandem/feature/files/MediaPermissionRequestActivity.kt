package dev.tandem.feature.files

import android.os.Bundle
import androidx.activity.result.contract.ActivityResultContracts
import dev.tandem.core.ui.TandemActivity

/** Transparent trampoline that shows the system media permission request (and re-selection picker). */
class MediaPermissionRequestActivity : TandemActivity() {
    private val requestPermissions =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { finish() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestPermissions.launch(MediaPermissionChecker(this).requiredPermissions().toTypedArray())
    }
}
