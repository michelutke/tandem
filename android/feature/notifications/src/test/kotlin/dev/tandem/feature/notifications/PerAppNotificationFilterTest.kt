package dev.tandem.feature.notifications

import android.app.Notification
import android.os.Process
import android.service.notification.StatusBarNotification
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.storage.settings.SettingsStore
import dev.tandem.core.testing.FakeElapsedRealtime
import dev.tandem.core.transport.FakeTandemSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import java.io.File
import java.time.Instant

// E30-04 tdd:
//   unit: perAppFilter_denyToggled_nextNotificationDropped
//   unit: perAppFilter_allowOnSystemNoisePackage_nextNotificationForwarded
//   unit: perAppFilter_newInstanceOverSameDataStore_denyPersisted
//   unit: perAppFilter_denyToggledWhileConnected_appliesWithZeroReconnects
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class PerAppNotificationFilterTest {
    @Test
    fun perAppFilter_denyToggled_nextNotificationDropped() =
        runTest {
            val filter = newFilter()
            assertTrue(filter.shouldForward(sbn("com.example.chat"), OWN_PACKAGE))

            filter.setOverride("com.example.chat", FilterOverride.DENY)
            runCurrent()

            assertFalse(filter.shouldForward(sbn("com.example.chat"), OWN_PACKAGE))
        }

    @Test
    fun perAppFilter_allowOnSystemNoisePackage_nextNotificationForwarded() =
        runTest {
            val filter = newFilter()
            assertFalse(filter.shouldForward(sbn("com.android.systemui"), OWN_PACKAGE))

            filter.setOverride("com.android.systemui", FilterOverride.ALLOW)
            runCurrent()

            assertTrue(filter.shouldForward(sbn("com.android.systemui"), OWN_PACKAGE))
        }

    @Test
    fun perAppFilter_newInstanceOverSameDataStore_denyPersisted() =
        runTest {
            val file = File(RuntimeEnvironment.getApplication().filesDir, "notification-overrides.preferences_pb")

            val firstScope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
            val firstFilter = filterOver(file, firstScope)
            firstFilter.setOverride("com.example.chat", FilterOverride.DENY)
            runCurrent()
            firstScope.cancel()

            val secondScope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
            val secondFilter = filterOver(file, secondScope)
            runCurrent()

            assertFalse(secondFilter.shouldForward(sbn("com.example.chat"), OWN_PACKAGE))
            secondScope.cancel()
        }

    @Test
    fun perAppFilter_denyToggledWhileConnected_appliesWithZeroReconnects() =
        runTest {
            val filter = newFilter()
            val session = FakeTandemSession()
            val dispatcher = StandardTestDispatcher(testScheduler)
            val sink = NotificationSink(session, FakeElapsedRealtime(testScheduler), dispatcher)
            session.emitState(ConnectionState.Ready(connectedAt = Instant.EPOCH))
            runCurrent()

            postIfAllowed(filter, sink, "com.example.chat")
            runCurrent()
            assertEquals(1, session.sentFrames.size)

            filter.setOverride("com.example.chat", FilterOverride.DENY)
            runCurrent()
            assertEquals(ConnectionState.Ready(connectedAt = Instant.EPOCH), session.state.value)

            postIfAllowed(filter, sink, "com.example.chat")
            runCurrent()

            // Still connected, no reconnect observed, and the newly-denied package's second
            // notification never reached the session.
            assertEquals(ConnectionState.Ready(connectedAt = Instant.EPOCH), session.state.value)
            assertEquals(1, session.sentFrames.size)
        }

    @Test
    fun perAppFilterRows_threeInstalledApps_matchesEachAppsCurrentState() =
        runTest {
            val filter = newFilter()
            filter.setOverride("com.example.chat", FilterOverride.DENY)
            filter.setOverride("com.android.systemui", FilterOverride.ALLOW)
            runCurrent()

            val installedApps =
                listOf(
                    InstalledApp("com.example.chat", "Chat"),
                    InstalledApp("com.example.social", "Social"),
                    InstalledApp("com.android.systemui", "System UI"),
                )

            val rows = filter.rowsFor(FakeInstalledAppsSource(installedApps).installedApps())

            assertEquals(
                listOf(
                    PerAppFilterRow("com.example.chat", "Chat", allowed = false),
                    PerAppFilterRow("com.example.social", "Social", allowed = true),
                    PerAppFilterRow("com.android.systemui", "System UI", allowed = true),
                ),
                rows,
            )
        }

    private fun TestScope.newFilter(): PerAppNotificationFilter {
        val name = "notification-overrides-${System.nanoTime()}.preferences_pb"
        val file = File(RuntimeEnvironment.getApplication().filesDir, name)
        return filterOver(file, CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler)))
    }

    private fun filterOver(
        file: File,
        scope: CoroutineScope,
    ): PerAppNotificationFilter {
        val dataStore = PreferenceDataStoreFactory.create(scope = scope) { file }
        return PerAppNotificationFilter(SettingsStore(dataStore), scope)
    }

    private fun postIfAllowed(
        filter: PerAppNotificationFilter,
        sink: NotificationSink,
        packageName: String,
    ) {
        val sbn = sbn(packageName)
        if (filter.shouldForward(sbn, OWN_PACKAGE)) {
            sink.onNotificationPosted(NotificationMapper.toPosted(sbn, appVersionCode = 0))
        }
    }

    @Suppress("DEPRECATION")
    private fun sbn(packageName: String): StatusBarNotification =
        StatusBarNotification(
            packageName,
            packageName,
            1,
            "tag",
            Process.myUid(),
            Process.myPid(),
            0,
            plainNotification(),
            Process.myUserHandle(),
            System.currentTimeMillis(),
        )

    private fun plainNotification(): Notification =
        Notification
            .Builder(RuntimeEnvironment.getApplication(), "test-channel")
            .setContentTitle("Alice")
            .setContentText("On my way")
            .build()

    private companion object {
        const val OWN_PACKAGE = "dev.tandem.app"
    }
}
