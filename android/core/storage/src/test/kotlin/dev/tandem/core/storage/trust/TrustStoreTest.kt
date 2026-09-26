package dev.tandem.core.storage.trust

import android.database.sqlite.SQLiteDatabase
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

    /**
     * Copies the committed v1 fixture (`src/test/resources/trust_v1_fixture.db`, generated
     * against schema v1's identity hash, E13-03) to [destination] so each test mutates its own
     * copy rather than the shared classpath resource.
     */
    private fun copyV1Fixture(destination: File) {
        val resource =
            requireNotNull(javaClass.classLoader?.getResourceAsStream("trust_v1_fixture.db")) {
                "trust_v1_fixture.db missing from test resources"
            }
        resource.use { input -> destination.outputStream().use { output -> input.copyTo(output) } }
    }

    @Test
    fun migration_v1FixtureOpened_allRecordsReadableVersionStill1() =
        runTest {
            val context = RuntimeEnvironment.getApplication()
            val dbFile = File(tempFolder.root, "trust_v1_fixture.db")
            copyV1Fixture(dbFile)

            val fixture = TrustStore.open(context, dbFile)
            val records = fixture.list()
            fixture.close()

            assertEquals(2, records.size)
            assertEquals(
                setOf("device-a", "device-b"),
                records.map { it.deviceId }.toSet(),
            )

            val rawDb = SQLiteDatabase.openOrCreateDatabase(dbFile.absolutePath, null)
            assertEquals(1, rawDb.version)
            rawDb.close()
        }

    @Test
    fun migration_v1FixtureToSimulatedV2_allRecordsPreservedNewFieldDefaulted() =
        runTest {
            val context = RuntimeEnvironment.getApplication()
            val dbFile = File(tempFolder.root, "trust_v1_to_v2.db")
            copyV1Fixture(dbFile)

            val db = SimulatedV2TrustDatabase.open(context, dbFile, SIMULATED_MIGRATION_1_TO_2)
            val records = db.list()
            db.close()

            assertEquals(2, records.size)

            val first = records.single { it.deviceId == "device-a" }
            assertEquals("Phone A", first.displayName)
            assertEquals(1000L, first.pairedAtEpochMs)
            assertEquals(2000L, first.lastSeenEpochMs)
            assertEquals("notify,clipboard", first.capabilitiesCsv)
            assertEquals("", first.additionalData)

            val second = records.single { it.deviceId == "device-b" }
            assertEquals("Phone B", second.displayName)
            assertEquals(1500L, second.pairedAtEpochMs)
            assertEquals(2500L, second.lastSeenEpochMs)
            assertEquals("notify", second.capabilitiesCsv)
            assertEquals("", second.additionalData)
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
