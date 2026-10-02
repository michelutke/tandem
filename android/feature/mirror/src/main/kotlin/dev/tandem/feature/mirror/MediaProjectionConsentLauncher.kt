package dev.tandem.feature.mirror

import android.content.Intent
import android.media.projection.MediaProjectionManager

/**
 * Real [ProjectionConsentLauncher] (E61-02): builds a fresh `createScreenCaptureIntent` per launch
 * and hands it to [launchIntent] (an activity-result launcher owned by the UI layer).
 */
class MediaProjectionConsentLauncher(
    private val projectionManager: MediaProjectionManager,
    private val launchIntent: (Intent) -> Unit,
) : ProjectionConsentLauncher {
    override fun launchConsent() {
        launchIntent(projectionManager.createScreenCaptureIntent())
    }
}
