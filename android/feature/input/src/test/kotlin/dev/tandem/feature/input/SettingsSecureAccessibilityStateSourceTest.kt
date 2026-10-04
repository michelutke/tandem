package dev.tandem.feature.input

import android.app.Application
import android.provider.Settings
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SettingsSecureAccessibilityStateSourceTest {
    private val application = ApplicationProvider.getApplicationContext<Application>()
    private val source = SettingsSecureAccessibilityStateSource(application)

    private fun setEnabledServices(value: String?) {
        Settings.Secure.putString(application.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, value)
    }

    @Test
    fun isServiceEnabled_settingAbsent_returnsFalse() {
        setEnabledServices(null)

        assertFalse(source.isServiceEnabled())
    }

    @Test
    fun isServiceEnabled_onlyOtherServicesEnabled_returnsFalse() {
        setEnabledServices("com.example/.Other:com.example.two/com.example.two.Svc")

        assertFalse(source.isServiceEnabled())
    }

    @Test
    fun isServiceEnabled_tandemServiceListed_returnsTrue() {
        setEnabledServices("com.example/.Other:dev.tandem.app/dev.tandem.feature.input.TandemAccessibilityService")

        assertTrue(source.isServiceEnabled())
    }
}
