package dev.tandem.spike.trust.room

import java.io.File
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

/**
 * Plain JUnit5 on the JVM -- no Robolectric, no Android framework class, no emulator. Room's
 * `BundledSQLiteDriver` (androidx.sqlite:sqlite-bundled) ships a JNI SQLite build for the host
 * OS/arch, so this runs the *same* SQLite Room would use on-device.
 */
class RoomTrustStoreTest {

    @TempDir
    lateinit var tempDir: File

    private lateinit var store: RoomTrustStore

    private fun record(fingerprint: String, seen: Long = 1_000L) = PeerRecord(
        deviceId = "device-$fingerprint",
        displayName = "Phone $fingerprint",
        spkiSha256Hex = fingerprint,
        pairedAtEpochMs = 500L,
        lastSeenEpochMs = seen,
        capabilities = listOf("notify", "clipboard"),
    )

    @BeforeEach
    fun setUp() {
        store = RoomTrustStore.openInMemory()
    }

    @AfterEach
    fun tearDown() {
        store.close()
    }

    @Test
    fun putThenGetByFingerprint_returnsEqualRecord() = runTest {
        val record = record("aa")

        store.put(record)

        assertEquals(record, store.get("aa"))
    }

    @Test
    fun getUnknownFingerprint_returnsNull() = runTest {
        assertNull(store.get("does-not-exist"))
    }

    @Test
    fun listAfterTwoPuts_returnsBothRecords() = runTest {
        store.put(record("aa"))
        store.put(record("bb"))

        val listed = store.list()
        assertEquals(2, listed.size)
        assertEquals(setOf("aa", "bb"), listed.map { it.spkiSha256Hex }.toSet())
    }

    @Test
    fun putExistingFingerprint_replacesRecordWithLatestFields() = runTest {
        store.put(record("aa", seen = 1_000L))

        store.put(record("aa", seen = 2_000L))

        val listed = store.list()
        assertEquals(1, listed.size)
        assertEquals(2_000L, listed.single().lastSeenEpochMs)
    }

    @Test
    fun reopenedFromSameFile_recordsPersist() = runTest {
        val dbFile = File(tempDir, "trust.db")
        val first = RoomTrustStore.open(dbFile)
        first.put(record("aa"))
        first.close()

        val reopened = RoomTrustStore.open(dbFile)
        val fetched = reopened.get("aa")
        reopened.close()

        assertEquals(record("aa"), fetched)
    }

    @Test
    fun unpair_thenGetSameProcess_returnsNull() = runTest {
        store.put(record("aa"))
        store.put(record("bb"))

        store.delete("aa")

        assertNull(store.get("aa"))
        assertEquals(1, store.list().size)
    }

    @Test
    fun unpair_thenReopenStore_recordStillAbsent() = runTest {
        val dbFile = File(tempDir, "trust.db")
        val first = RoomTrustStore.open(dbFile)
        first.put(record("aa"))
        first.delete("aa")
        first.close()

        val reopened = RoomTrustStore.open(dbFile)
        val fetched = reopened.get("aa")
        reopened.close()

        assertNull(fetched)
    }

    @Test
    fun swapPin_replacesOldFingerprintWithNewInOneTransaction() = runTest {
        store.put(record("old-fp"))

        store.swapPin("old-fp", record("new-fp"))

        assertNull(store.get("old-fp"))
        assertEquals("new-fp", store.get("new-fp")?.spkiSha256Hex)
        assertEquals(1, store.list().size)
    }
}
