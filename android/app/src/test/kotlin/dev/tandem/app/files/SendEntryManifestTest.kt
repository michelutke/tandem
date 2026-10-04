package dev.tandem.app.files

import android.content.ComponentName
import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment

// E40-11 tdd:
//   ci: mergedManifest_shareActivity_exportsSendAndSendMultipleFilters
@RunWith(AndroidJUnit4::class)
class SendEntryManifestTest {
    // Genuinely implicit on purpose: resolves exactly what another app's share sheet sends.
    @Suppress("ImplicitInternalIntent")
    @Test
    fun mergedManifest_shareActivity_exportsSendAndSendMultipleFilters() {
        val context = RuntimeEnvironment.getApplication()
        val packageManager = context.packageManager

        listOf(Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE).forEach { action ->
            val resolutions = packageManager.queryIntentActivities(Intent(action).setType("image/png"), 0)
            val share = resolutions.single { it.activityInfo.name == SHARE_ACTIVITY }
            assertTrue(action, share.activityInfo.exported)
        }
        val picker = packageManager.getActivityInfo(ComponentName(context, PICKER_ACTIVITY), 0)
        assertFalse(picker.exported)
    }

    private companion object {
        const val SHARE_ACTIVITY = "dev.tandem.feature.files.ShareFilesActivity"
        const val PICKER_ACTIVITY = "dev.tandem.feature.files.PickFilesActivity"
    }
}
