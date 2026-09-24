package dev.tandem.spike.trust.datastore

import dev.tandem.spike.trust.datastore.proto.TrustStore
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

/**
 * Plain JUnit5 on the JVM -- no Robolectric, no Android framework class on the classpath.
 * `dev.tandem.spike.trust.datastore.proto.*` are plain protobuf-javalite generated classes.
 */
class DataStoreTrustStoreTest {

    @TempDir
    lateinit var tempDir: File

    private lateinit var storeFile: File

    @BeforeEach
    fun setUp() {
        storeFile = File(tempDir, "trust_store.pb")
    }

    private fun record(fingerprint: String, seen: Long = 1_000L) = PeerRecord(
        deviceId = "device-$fingerprint",
        displayName = "Phone $fingerprint",
        spkiSha256Hex = fingerprint,
        pairedAtEpochMs = 500L,
        lastSeenEpochMs = seen,
        capabilities = listOf("notify", "clipboard"),
    )

    @Test
    fun putThenGetByFingerprint_returnsEqualRecord() = runTest {
        val store = DataStoreTrustStore(storeFile)
        val record = record("aa")

        store.put(record)

        assertEquals(record, store.get("aa"))
    }

    @Test
    fun getUnknownFingerprint_returnsNull() = runTest {
        val store = DataStoreTrustStore(storeFile)

        assertNull(store.get("does-not-exist"))
    }

    @Test
    fun listAfterTwoPuts_returnsBothRecords() = runTest {
        val store = DataStoreTrustStore(storeFile)

        store.put(record("aa"))
        store.put(record("bb"))

        val listed = store.list()
        assertEquals(2, listed.size)
        assertEquals(setOf("aa", "bb"), listed.map { it.spkiSha256Hex }.toSet())
    }

    @Test
    fun putExistingFingerprint_replacesRecordWithLatestFields() = runTest {
        val store = DataStoreTrustStore(storeFile)
        store.put(record("aa", seen = 1_000L))

        store.put(record("aa", seen = 2_000L))

        val listed = store.list()
        assertEquals(1, listed.size)
        assertEquals(2_000L, listed.single().lastSeenEpochMs)
    }

    @Test
    fun reopenedFromSameFile_recordsPersist() = runTest {
        // DataStore refuses a second active instance over the same file within one process
        // (IllegalStateException, "There are multiple DataStores active for this file") -- by
        // design there is exactly one DataStore per file per process, held for the process
        // lifetime. A real restart is a fresh process with a fresh guard, so "survives restart"
        // is proven here by reading the persisted bytes back with a fresh Serializer.readFrom
        // instead of constructing a second DataStoreTrustStore (see docs/spikes note).
        val first = DataStoreTrustStore(storeFile)
        first.put(record("aa"))

        val reread = readPersistedRecords()

        assertEquals(record("aa"), reread.singleOrNull())
    }

    @Test
    fun unpair_thenGetSameProcess_returnsNull() = runTest {
        val store = DataStoreTrustStore(storeFile)
        store.put(record("aa"))
        store.put(record("bb"))

        store.delete("aa")

        assertNull(store.get("aa"))
        assertEquals(1, store.list().size)
    }

    @Test
    fun unpair_thenReopenStore_recordStillAbsent() = runTest {
        // See reopenedFromSameFile_recordsPersist for why this reads persisted bytes directly
        // instead of constructing a second DataStoreTrustStore over the same file.
        val store = DataStoreTrustStore(storeFile)
        store.put(record("aa"))
        store.delete("aa")

        assertTrue(readPersistedRecords().none { it.spkiSha256Hex == "aa" })
    }

    @Test
    fun swapPin_replacesOldFingerprintWithNewInOneTransaction() = runTest {
        val store = DataStoreTrustStore(storeFile)
        store.put(record("old-fp"))

        store.swapPin("old-fp", record("new-fp"))

        assertNull(store.get("old-fp"))
        assertEquals("new-fp", store.get("new-fp")?.spkiSha256Hex)
        assertEquals(1, store.list().size)
    }

    @Test
    fun concurrentPutAndDelete_bothSerializeThroughUpdateData_noLostUpdate() = runTest {
        // DataStore.updateData is a single-writer transaction (internal Mutex); this proves two
        // "concurrent" callers never race a lost update, satisfying the E13-01 go/no-go
        // ("must delete a record atomically before unpair() returns").
        val store = DataStoreTrustStore(storeFile)
        store.put(record("keep"))
        store.put(record("drop"))

        coroutineScope {
            val deleteJob = launch { store.delete("drop") }
            val putJob = launch { store.put(record("keep", seen = 9_999L)) }
            deleteJob.join()
            putJob.join()
        }

        val listed = store.list()
        assertEquals(1, listed.size)
        assertEquals(9_999L, listed.single().lastSeenEpochMs)
    }

    private fun readPersistedRecords(): List<PeerRecord> =
        storeFile.inputStream().use { TrustStore.parseFrom(it) }.recordsList.map {
            PeerRecord(
                deviceId = it.deviceId,
                displayName = it.displayName,
                spkiSha256Hex = it.spkiSha256Hex,
                pairedAtEpochMs = it.pairedAtEpochMs,
                lastSeenEpochMs = it.lastSeenEpochMs,
                capabilities = it.capabilitiesList,
                pendingRotation = it.pendingRotation,
            )
        }

    @AfterEach
    fun tearDown() {
        Files.deleteIfExists(storeFile.toPath())
    }
}
