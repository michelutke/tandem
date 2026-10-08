package dev.tandem.app.settings

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import dev.tandem.app.connection.GatedSessionFeature
import dev.tandem.app.connection.SessionFeature
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.storage.settings.SettingsStore
import dev.tandem.core.transport.FakeTandemSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File

// Home feature switches:
//   unit: featureToggles_freshInstall_everyFeatureOn
//   unit: featureToggles_setOff_persistsAndReportsOff
//   unit: gatedSessionFeature_toggledOffAndOn_detachesThenReattaches
@OptIn(ExperimentalCoroutinesApi::class)
class FeatureTogglesTest {
    @TempDir
    lateinit var tempDir: File

    private var scope: CoroutineScope? = null

    @AfterEach
    fun tearDown() {
        scope?.cancel()
    }

    private fun TestScope.toggles(): FeatureToggles {
        val toggleScope = CoroutineScope(UnconfinedTestDispatcher(testScheduler) + SupervisorJob())
        scope = toggleScope
        val dataStore =
            PreferenceDataStoreFactory.create(scope = toggleScope) { File(tempDir, "toggles.preferences_pb") }
        return FeatureToggles(SettingsStore(dataStore), toggleScope)
    }

    @Test
    fun featureToggles_autoCapture_offByDefaultAndPersistsWhenSet() =
        runTest {
            val toggles = toggles()
            assertEquals(false, toggles.autoCapture.value)

            toggles.setAutoCapture(true)

            assertEquals(true, toggles.autoCapture.value)
        }

    @Test
    fun featureToggles_freshInstall_everyFeatureOn() =
        runTest {
            val toggles = toggles()

            SyncFeature.entries.forEach { assertEquals(true, toggles.enabled(it).first()) }
        }

    @Test
    fun featureToggles_setOff_persistsAndReportsOff() =
        runTest {
            val toggles = toggles()

            toggles.set(SyncFeature.Mirroring, false)

            assertEquals(false, toggles.isEnabled(SyncFeature.Mirroring))
            assertEquals(true, toggles.isEnabled(SyncFeature.Clipboard))
        }

    @Test
    fun gatedSessionFeature_toggledOffAndOn_detachesThenReattaches() =
        runTest {
            val enabled = MutableStateFlow(true)
            var attached = 0
            var detached = 0
            val inner =
                SessionFeature { _, _, _ ->
                    attached++
                    try {
                        awaitCancellation()
                    } finally {
                        detached++
                    }
                }
            val job =
                launch(UnconfinedTestDispatcher(testScheduler)) {
                    GatedSessionFeature(inner, enabled).run(FakeTandemSession(), SpkiFingerprint(ByteArray(32)), null)
                }

            enabled.value = false
            assertEquals(1 to 1, attached to detached)
            enabled.value = true
            assertEquals(2 to 1, attached to detached)

            job.cancel()
        }
}
