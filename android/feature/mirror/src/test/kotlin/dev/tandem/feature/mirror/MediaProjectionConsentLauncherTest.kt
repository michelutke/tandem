package dev.tandem.feature.mirror

import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment

/** MediaProjectionConsentLauncher test (E61-02), on Robolectric (E00-20). */
@RunWith(AndroidJUnit4::class)
class MediaProjectionConsentLauncherTest {
    @Test
    fun mediaProjectionConsentLauncher_eachLaunch_handsScreenCaptureIntentToLauncher() {
        val context = RuntimeEnvironment.getApplication()
        val manager = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val launched = mutableListOf<Intent>()
        val launcher = MediaProjectionConsentLauncher(manager, launched::add)

        launcher.launchConsent()
        launcher.launchConsent()

        assertEquals(2, launched.size)
        launched.forEach { assertNotNull(it.component ?: it.action) }
    }
}
