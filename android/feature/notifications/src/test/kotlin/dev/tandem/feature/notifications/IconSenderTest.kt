package dev.tandem.feature.notifications

import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.core.storage.settings.SettingsStore
import dev.tandem.protocol.v1.IconData
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import java.io.File

/**
 * `IconSender` tests (E30-05; `docs/planning/backlog/phase-3.yaml` E30-05's `tdd:` list). Mirrors
 * `SettingsStoreTest`'s pattern for modeling a restart: cancel the first `SettingsStore`'s backing
 * scope, then open a fresh one over the same file. `PreferenceDataStoreFactory` is pure
 * Kotlin/JVM, but this module's Robolectric setup requires `AndroidJUnit4` for every test class in
 * this source set (`isIncludeAndroidResources`), so this class runs under it too even though
 * nothing here touches a framework API besides the `ColorDrawable` fake icon.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class IconSenderTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    @Test
    fun iconSender_firstNotificationForPackageVersion_sendsOneIconData() =
        runTest {
            val sender = newSender(dataStoreFile())
            val sent = mutableListOf<IconData>()

            sender.onNotificationPosted("com.example.chat", 1L, icon()) { sent += it }
            runCurrent()

            assertEquals(1, sent.size)
            assertEquals("com.example.chat", sent.single().packageName)
            assertEquals(1L, sent.single().versionCode)
        }

    @Test
    fun iconSender_fiveNotificationsSameVersion_iconDataSentOnce() =
        runTest {
            val sender = newSender(dataStoreFile())
            val sent = mutableListOf<IconData>()

            repeat(5) {
                sender.onNotificationPosted("com.example.chat", 1L, icon()) { sent += it }
                runCurrent()
            }

            assertEquals(1, sent.size)
        }

    @Test
    fun iconSender_versionCodeIncremented_sendsNewIconData() =
        runTest {
            val sender = newSender(dataStoreFile())
            val sent = mutableListOf<IconData>()

            sender.onNotificationPosted("com.example.chat", 1L, icon()) { sent += it }
            runCurrent()
            sender.onNotificationPosted("com.example.chat", 2L, icon()) { sent += it }
            runCurrent()

            assertEquals(2, sent.size)
            assertEquals(listOf(1L, 2L), sent.map { it.versionCode })
        }

    @Test
    fun iconSender_recordReloadedAfterRestart_iconNotResent() =
        runTest {
            val file = dataStoreFile()
            val firstScope = CoroutineScope(UnconfinedTestDispatcher(testScheduler) + SupervisorJob())
            val firstSender =
                IconSender(
                    SettingsStore(PreferenceDataStoreFactory.create(scope = firstScope) { file }),
                    UnconfinedTestDispatcher(testScheduler),
                )
            firstSender.onNotificationPosted("com.example.chat", 1L, icon()) {}
            runCurrent()
            firstSender.close()
            firstScope.cancel()

            val secondScope = CoroutineScope(UnconfinedTestDispatcher(testScheduler) + SupervisorJob())
            val secondSender =
                IconSender(
                    SettingsStore(PreferenceDataStoreFactory.create(scope = secondScope) { file }),
                    UnconfinedTestDispatcher(testScheduler),
                )
            val sent = mutableListOf<IconData>()
            secondSender.onNotificationPosted("com.example.chat", 1L, icon()) { sent += it }
            runCurrent()

            assertTrue(sent.isEmpty())
            secondSender.close()
            secondScope.cancel()
        }

    private fun TestScope.newSender(file: File): IconSender {
        val storeScope = CoroutineScope(UnconfinedTestDispatcher(testScheduler) + SupervisorJob())
        val dataStore = PreferenceDataStoreFactory.create(scope = storeScope) { file }
        return IconSender(SettingsStore(dataStore), UnconfinedTestDispatcher(testScheduler))
    }

    private fun dataStoreFile(): File = File(tempFolder.newFolder(), "icon_sent.preferences_pb")

    private fun icon() = ColorDrawable(Color.RED)
}
