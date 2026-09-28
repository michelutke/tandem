package dev.tandem.app.clipboard

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment

/**
 * E31-06 tdd:
 *   unit: intentResolution_actionSendAndProcessText_resolveToTandemActivities
 *
 * A real `PackageManager` intent-resolution check against `:app`'s own merged manifest (same
 * Robolectric convention `TandemActivityTest.everyDeclaredActivity_extendsTandemActivity` uses):
 * resolves against `RuntimeEnvironment.getApplication()`'s `PackageManager`, so this only passes if
 * ShareTargetActivity/ProcessTextActivity are actually declared with matching intent filters in
 * `:app`'s manifest -- not merely that the classes exist.
 */
@RunWith(AndroidJUnit4::class)
class ClipboardEntryPointIntentResolutionTest {
    // Genuinely implicit on purpose: this is exactly the intent shape another app's share sheet /
    // text-selection menu sends, and the test's whole point is to resolve it, not target a
    // component directly (same reasoning as BootReceiverTest's identical suppress).
    @Suppress("ImplicitInternalIntent")
    @Test
    fun intentResolution_actionSendAndProcessText_resolveToTandemActivities() {
        val packageManager = RuntimeEnvironment.getApplication().packageManager

        val sendIntent = Intent(Intent.ACTION_SEND).apply { type = "text/plain" }
        val sendResolutions = packageManager.queryIntentActivities(sendIntent, 0)
        assertTrue(
            "expected an ACTION_SEND text/plain resolution to dev.tandem.feature.clipboard.ShareTargetActivity",
            sendResolutions.any { it.activityInfo.name == "dev.tandem.feature.clipboard.ShareTargetActivity" },
        )

        val processTextIntent = Intent(Intent.ACTION_PROCESS_TEXT).apply { type = "text/plain" }
        val processTextResolutions = packageManager.queryIntentActivities(processTextIntent, 0)
        assertTrue(
            "expected an ACTION_PROCESS_TEXT text/plain resolution to dev.tandem.feature.clipboard.ProcessTextActivity",
            processTextResolutions.any { it.activityInfo.name == "dev.tandem.feature.clipboard.ProcessTextActivity" },
        )
    }
}
