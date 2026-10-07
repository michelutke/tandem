package dev.tandem.app.onboarding

import android.app.Application
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BatteryExemptionLauncherTest {
    private class RecordingContext(
        base: Context,
        private val failFirst: Boolean,
    ) : ContextWrapper(base) {
        val started = mutableListOf<Intent>()

        override fun startActivity(intent: Intent) {
            started += intent
            if (failFirst && started.size == 1) throw ActivityNotFoundException()
        }
    }

    private val context: Application = ApplicationProvider.getApplicationContext()

    @Test
    fun launchBatteryExemption_activityResolves_startsDirectDialogForOwnPackage() {
        val recording = RecordingContext(context, failFirst = false)

        launchBatteryExemption(recording)

        assertEquals(1, recording.started.size)
        assertEquals(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, recording.started[0].action)
        assertEquals(Uri.parse("package:${context.packageName}"), recording.started[0].data)
    }

    @Test
    fun launchBatteryExemption_noActivityResolves_fallsBackToSettingsList() {
        val recording = RecordingContext(context, failFirst = true)

        launchBatteryExemption(recording)

        assertEquals(2, recording.started.size)
        assertEquals(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS, recording.started[1].action)
    }
}
