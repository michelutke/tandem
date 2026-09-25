package dev.tandem.app

import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dagger.hilt.internal.GeneratedComponentManagerHolder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

// instrumented (E00-03): runs on the real `TandemApplication` / generated Hilt component, not
// Robolectric's `HiltTestApplication` substitute (docs/planning/backlog/phase-0.yaml E00-03
// notes), so a broken real `@HiltAndroidApp` component would fail here instead of only surfacing
// in the shipped APK.
@RunWith(AndroidJUnit4::class)
class TandemApplicationInstrumentedTest {
    @Test
    fun tandemApplication_launchMainActivity_activityReachesResumedState() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            assertEquals(Lifecycle.State.RESUMED, scenario.state)
        }
    }

    @Test
    fun tandemApplication_onCreate_isHiltComponentManager() {
        // Typed as Any: the Hilt Gradle plugin rewrites TandemApplication's superclass to the
        // generated Hilt_TandemApplication in bytecode, which the compiler cannot see.
        val application: Any = ApplicationProvider.getApplicationContext<TandemApplication>()

        assertTrue(application is GeneratedComponentManagerHolder)
    }
}
