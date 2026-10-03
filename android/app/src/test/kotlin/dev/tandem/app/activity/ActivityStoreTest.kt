package dev.tandem.app.activity

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.PeerDataPurgeRegistry
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

// E20-18 tdd:
//   unit: activityStore_clipboardEvent_storesNoContentField
//   unit: activityStore_entryOlderThan7Days_purged
//   unit: activityStore_unpairCompleted_feedCleared
@OptIn(ExperimentalCoroutinesApi::class)
class ActivityStoreTest {
    @TempDir
    lateinit var tempDir: File

    private var scope: CoroutineScope? = null

    @AfterEach
    fun tearDown() {
        scope?.cancel()
    }

    private fun TestScope.store(clock: TestClock = TestClock(testScheduler, NOW)): ActivityStore {
        val storeScope = CoroutineScope(UnconfinedTestDispatcher(testScheduler) + SupervisorJob())
        scope = storeScope
        val dataStore =
            PreferenceDataStoreFactory.create(scope = storeScope) { File(tempDir, "activity.preferences_pb") }
        return ActivityStore(dataStore, clock)
    }

    @Test
    fun activityStore_clipboardEvent_storesNoContentField() =
        runTest {
            val fields =
                ActivityEntry::class.java.declaredFields
                    .filterNot { it.name.startsWith("\$") }
                    .map { it.name }
                    .toSet()
            assertEquals(setOf("type", "sizeBytes", "durationSeconds", "timestamp"), fields)

            val store = store()
            store.record(ActivityEntry(ActivityEventType.ClipboardFromMac, null, null, NOW.minusSeconds(3600)))
            val entries = store.entries.first()
            assertEquals(1, entries.size)
            assertEquals(ActivityEventType.ClipboardFromMac, entries.single().type)
            assertEquals(null, entries.single().sizeBytes)
        }

    @Test
    fun activityStore_entryOlderThan7Days_purged() =
        runTest {
            val clock = TestClock(testScheduler, NOW)
            val store = store(clock)
            val now = clock.instant()
            store.record(ActivityEntry(ActivityEventType.FileReceived, 10, null, now.minus(Duration.ofDays(8))))
            store.record(ActivityEntry(ActivityEventType.FindPhone, null, 5, now.minus(Duration.ofDays(6))))

            store.purgeExpired()

            val entries = store.entries.first()
            assertEquals(listOf(ActivityEventType.FindPhone), entries.map { it.type })
        }

    @Test
    fun activityStore_unpairCompleted_feedCleared() =
        runTest {
            val store = store()
            store.record(ActivityEntry(ActivityEventType.Mirroring, null, 60, NOW.minusSeconds(3600)))
            val registry = PeerDataPurgeRegistry().apply { register(store) }

            registry.purgeAll(SpkiFingerprint(ByteArray(32)))

            assertEquals(emptyList<ActivityEntry>(), store.entries.first())
        }

    private companion object {
        val NOW: Instant = Instant.parse("2026-01-10T12:00:00Z")
    }
}
