package dev.tandem.feature.input

import android.provider.Settings
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith

// E62-02 tdd: instrumented: accessibilityService_freshInstall_notInEnabledServices
@RunWith(AndroidJUnit4::class)
class AccessibilityServiceInstrumentedTest {
    @Test
    fun accessibilityService_freshInstall_notInEnabledServices() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val enabledServices =
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES).orEmpty()

        assertFalse(enabledServices.contains(TandemAccessibilityService::class.java.name))
        assertFalse(SettingsSecureAccessibilityStateSource(context).isServiceEnabled())
    }
}
