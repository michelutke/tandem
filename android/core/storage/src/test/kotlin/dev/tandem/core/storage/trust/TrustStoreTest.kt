package dev.tandem.core.storage.trust

import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.core.crypto.SpkiFingerprint
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import java.io.File

/**
 * Runs on Robolectric (E00-20) rather than plain JUnit5, because Room's Android-variant
 * `Room.databaseBuilder`/`inMemoryDatabaseBuilder` require a working `Context` even with a driver
 * configured, and `AndroidSQLiteDriver` needs Robolectric's `android.database.sqlite` shadows to
 * open a database at all on a host JVM -- a deviation from the E13-01 spike's Finding 1, which was
 * proven only in a standalone, non-AGP `kotlin("jvm")` module (see TrustStore's KDoc for the
 * detailed reasoning and the coder's report for E13-02). `AndroidJUnit4` delegates to
 * `RobolectricTestRunner` off-device.
 */
@RunWith(AndroidJUnit4::class)
class TrustStoreTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    private lateinit var store: TrustStore

    private fun fingerprint(seed: Int) = SpkiFingerprint(ByteArray(32) { seed.toByte() })

    private fun record(
        seed: Int,
        seen: Long = 1_000L,
    ) = PeerRecord(
        deviceId = "device-$seed",
        displayName = "Phone $seed",
        spkiSha256Base64Url = fingerprint(seed).base64Url,
        pairedAtEpochMs = 500L,
        lastSeenEpochMs = seen,
        capabilities = listOf("notify", "clipboard"),
    )

    @Before
    fun setUp() {
        store = TrustStore.openInMemory(RuntimeEnvironment.getApplication())
    }

    @After
    fun tearDown() {
        store.close()
    }

    @Test
    fun trustStore_putThenGetByFingerprint_returnsEqualRecord() =
        runTest {
            val record = record(seed = 1)

            store.put(record)

            assertEquals(record, store.get(fingerprint(1)))
        }

    @Test
    fun trustStore_getUnknownFingerprint_returnsNull() =
        runTest {
            assertNull(store.get(fingerprint(1)))
        }

    @Test
    fun trustStore_listAfterTwoPuts_returnsBothRecords() =
        runTest {
            store.put(record(seed = 1))
            store.put(record(seed = 2))

            val listed = store.list()

            assertEquals(2, listed.size)
            assertEquals(
                setOf(fingerprint(1).base64Url, fingerprint(2).base64Url),
                listed.map { it.spkiSha256Base64Url }.toSet(),
            )
        }

    @Test
    fun trustStore_putExistingFingerprint_singleRecordWithLatestFields() =
        runTest {
            store.put(record(seed = 1, seen = 1_000L))

            store.put(record(seed = 1, seen = 2_000L))

            val listed = store.list()
            assertEquals(1, listed.size)
            assertEquals(2_000L, listed.single().lastSeenEpochMs)
        }

    @Test
    fun trustStore_reopenedFromSameFile_recordsPersist() =
        runTest {
            val context = RuntimeEnvironment.getApplication()
            val dbFile = File(tempFolder.root, "trust.db")
            val first = TrustStore.open(context, dbFile)
            first.put(record(seed = 1))
            first.close()

            val reopened = TrustStore.open(context, dbFile)
            val fetched = reopened.get(fingerprint(1))
            reopened.close()

            assertEquals(record(seed = 1), fetched)
        }

    @Test
    fun trustStore_deleteThenGet_returnsNull() =
        runTest {
            store.put(record(seed = 1))
            store.put(record(seed = 2))

            store.delete(fingerprint(1))

            assertNull(store.get(fingerprint(1)))
            assertEquals(1, store.list().size)
        }

    @Test
    fun spkiFingerprintKey_not32Bytes_throwsIllegalArgument() {
        assertThrows(IllegalArgumentException::class.java) {
            SpkiFingerprint(ByteArray(31))
        }
    }

    @Test
    fun unpair_thenGetSameProcess_returnsNull() =
        runTest {
            store.put(record(seed = 1))

            store.unpair(fingerprint(1))

            assertNull(store.get(fingerprint(1)))
        }

    @Test
    fun unpair_thenReopenStore_recordStillAbsent() =
        runTest {
            val context = RuntimeEnvironment.getApplication()
            val dbFile = File(tempFolder.root, "trust.db")
            val first = TrustStore.open(context, dbFile)
            first.put(record(seed = 1))
            first.unpair(fingerprint(1))
            first.close()

            val reopened = TrustStore.open(context, dbFile)
            val fetched = reopened.get(fingerprint(1))
            reopened.close()

            assertNull(fetched)
        }

    @Test
    fun unpair_otherPeerRecords_remainUnchanged() =
        runTest {
            store.put(record(seed = 1))
            store.put(record(seed = 2))
            store.put(record(seed = 3))

            store.unpair(fingerprint(2))

            assertEquals(2, store.list().size)
            assertEquals(record(seed = 1), store.get(fingerprint(1)))
            assertEquals(record(seed = 3), store.get(fingerprint(3)))
            assertNull(store.get(fingerprint(2)))
        }
}
