package dev.tandem.app.mirror

import android.content.Intent
import android.os.Bundle
import androidx.activity.result.contract.ActivityResultContracts
import dev.tandem.core.ui.TandemActivity
import dev.tandem.feature.mirror.MirrorPromptActionDispatcher

/**
 * Process-wide hand-off between [AndroidMirrorPlatform] and [MirrorConsentActivity]: the platform
 * installs [sink] for the consent outcome and its launcher parks the `createScreenCaptureIntent`
 * in [pendingConsentIntent] for the activity to launch.
 */
object MirrorConsentResults {
    @Volatile
    var sink: ((resultCode: Int, data: Intent?) -> Unit)? = null

    @Volatile
    var pendingConsentIntent: Intent? = null

    fun takePendingConsentIntent(): Intent? {
        val intent = pendingConsentIntent
        pendingConsentIntent = null
        return intent
    }
}

/**
 * Transparent host for the system MediaProjection consent dialog (E62-11), opened directly by the
 * prompt notification's Start action (an activity trampoline, not a receiver). It reports the tap
 * to the prompt controller, launches the consent intent that produced and forwards the result.
 * Not exported: reached only by the explicit-component PendingIntent the prompt notification builds.
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
        MirrorConsentResults.pendingConsentIntent = null
        MirrorPromptActionDispatcher.controller?.onStartTapped()
        val consentIntent = MirrorConsentResults.takePendingConsentIntent()
        if (consentIntent == null) finish() else consent.launch(consentIntent)
    }
}
