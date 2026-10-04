package dev.tandem.feature.input

import android.app.Application
import android.provider.Settings
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf

// E62-02 tdd: unit: remoteInputSettings_openSettingsTapped_launchesAccessibilitySettingsIntent
@RunWith(AndroidJUnit4::class)
class AccessibilitySettingsLauncherTest {
    @Test
    fun remoteInputSettings_openSettingsTapped_launchesAccessibilitySettingsIntent() {
        val application = ApplicationProvider.getApplicationContext<Application>()

        AccessibilitySettingsLauncher(application).open()

        val startedIntent = shadowOf(application).nextStartedActivity
        assertEquals(Settings.ACTION_ACCESSIBILITY_SETTINGS, startedIntent?.action)
    }
}
