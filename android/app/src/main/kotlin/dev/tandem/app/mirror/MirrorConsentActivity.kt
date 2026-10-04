package dev.tandem.app.mirror

import android.content.Intent
import android.os.Bundle
import androidx.activity.result.contract.ActivityResultContracts
import dev.tandem.core.ui.TandemActivity

/** Process-wide sink for the system MediaProjection consent outcome; [AndroidMirrorPlatform] installs it. */
object MirrorConsentResults {
    @Volatile
    var sink: ((resultCode: Int, data: Intent?) -> Unit)? = null
}

/**
 * Transparent host for the system MediaProjection consent dialog (E62-11): launched with the
 * `createScreenCaptureIntent` the user's Start tap produced, forwards the result and finishes.
 * Not exported: reached only by [AndroidMirrorPlatform]'s explicit-component intent.
 */
class MirrorConsentActivity : TandemActivity() {
    private val consent =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            MirrorConsentResults.sink?.invoke(result.resultCode, result.data)
            finish()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) return
        val intent = intent.getParcelableExtra(EXTRA_CONSENT_INTENT, Intent::class.java)
        if (intent == null) finish() else consent.launch(intent)
    }

    companion object {
        const val EXTRA_CONSENT_INTENT = "dev.tandem.app.mirror.CONSENT_INTENT"
    }
}
