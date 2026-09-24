package dev.tandem.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment

// Robolectric JVM tests for Android framework types that plain JUnit5 unit tests cannot reach
// (CLAUDE.md Robolectric rule, E00-20). Runs on the JUnit Vintage engine alongside
// SampleJupiterTest's JUnit5 Jupiter test in the same `:app:testDebugUnitTest` report.
// `AndroidJUnit4` delegates to `RobolectricTestRunner` off-device.
@RunWith(AndroidJUnit4::class)
class RobolectricSampleTest {
    @Test
    fun robolectricSample_applicationContext_resolvesPackageName() {
        val context = RuntimeEnvironment.getApplication()

        assertEquals("dev.tandem.app", context.packageName)
    }

    @Test
    fun robolectricClipboard_setPrimaryClip_readBackSameText() {
        val context = RuntimeEnvironment.getApplication()
        val clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

        clipboardManager.setPrimaryClip(ClipData.newPlainText("label", "tandem-clip"))

        val readBack =
            clipboardManager.primaryClip
                ?.getItemAt(0)
                ?.text
                .toString()
        assertEquals("tandem-clip", readBack)
    }
}
