package dev.tandem.app.activity

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import dev.tandem.app.home.ActivityHomeRingStateSource
import dev.tandem.app.home.HomeRingState
import dev.tandem.core.testing.TestClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset

// Activity recording and the idle Home ring it feeds:
//   unit: activityRecorder_fileReceived_storesEntryWithClockTimestamp
//   unit: activityRecorder_mirroringWithDuration_storesDurationOnly
//   unit: homeRingSource_entriesToday_countsOnlyTodayAgainstSevenDayAverage
@OptIn(ExperimentalCoroutinesApi::class)
class ActivityRecorderTest {
    @TempDir
    lateinit var tempDir: File

    private var scope: CoroutineScope? = null

    @AfterEach
    fun tearDown() {
        scope?.cancel()
    }

    private fun TestScope.scopeAndStore(): Pair<CoroutineScope, ActivityStore> {
        val storeScope = CoroutineScope(UnconfinedTestDispatcher(testScheduler) + SupervisorJob())
        scope = storeScope
        val dataStore =
            PreferenceDataStoreFactory.create(scope = storeScope) { File(tempDir, "activity.preferences_pb") }
        return storeScope to ActivityStore(dataStore, TestClock(testScheduler, NOW))
    }

    @Test
    fun activityRecorder_fileReceived_storesEntryWithClockTimestamp() =
        runTest {
            val (storeScope, store) = scopeAndStore()
            val recorder = ActivityRecorder(store, storeScope, TestClock(testScheduler, NOW))

            recorder.record(ActivityEventType.FileReceived)

            val entry = store.entries.first().single()
            assertEquals(ActivityEventType.FileReceived, entry.type)
            assertEquals(NOW, entry.timestamp)
        }

    @Test
    fun activityRecorder_mirroringWithDuration_storesDurationOnly() =
        runTest {
            val (storeScope, store) = scopeAndStore()
            val recorder = ActivityRecorder(store, storeScope, TestClock(testScheduler, NOW))

            recorder.record(ActivityEventType.Mirroring, durationSeconds = 90)

            val entry = store.entries.first().single()
            assertEquals(90L, entry.durationSeconds)
            assertEquals(null, entry.sizeBytes)
        }

    @Test
    fun homeRingSource_entriesToday_countsOnlyTodayAgainstSevenDayAverage() =
        runTest {
            val (storeScope, store) = scopeAndStore()
            val clock = TestClock(testScheduler, NOW)
            store.record(ActivityEntry(ActivityEventType.FileReceived, null, null, NOW.minusSeconds(60)))
            store.record(ActivityEntry(ActivityEventType.FindPhone, null, null, NOW.minusSeconds(120)))
            store.record(ActivityEntry(ActivityEventType.FindPhone, null, null, NOW.minus(Duration.ofDays(3))))

            val source = ActivityHomeRingStateSource(store.entries, clock, storeScope, ZoneOffset.UTC)

            assertEquals(HomeRingState.Idle(itemsSyncedToday = 2, sevenDayAverage = 1), source.state.value)
        }

    private companion object {
        val NOW: Instant = Instant.parse("2026-01-10T12:00:00Z")
    }
}
