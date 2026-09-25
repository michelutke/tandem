package dev.tandem.spike.trust.datastore

import dev.tandem.spike.trust.datastore.proto.v1fixture.PeerRecordV1Proto
import dev.tandem.spike.trust.datastore.proto.v1fixture.TrustStoreV1Fixture
import java.io.File
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

/**
 * E13-03 migration scaffold, DataStore side: proto3 field addition is backward compatible by
 * construction. There is no explicit "migration runner" -- a store file written with the
 * `TrustStoreV1Fixture` shape (no `pending_rotation` field) is read back through the current
 * `TrustStoreSerializer`/`TrustStore` message and the new field defaults to `false`.
 */
class TrustStoreMigrationTest {

    @TempDir
    lateinit var tempDir: File

    @Test
    fun v1FixtureBytesOpenedWithCurrentSchema_allRecordsPreservedNewFieldDefaulted() = runTest {
        val storeFile = File(tempDir, "trust_store.pb")
        val v1Bytes = TrustStoreV1Fixture.newBuilder()
            .addRecords(
                PeerRecordV1Proto.newBuilder()
                    .setDeviceId("mac-1")
                    .setDisplayName("Michel's Mac")
                    .setSpkiSha256Hex("aa".repeat(32))
                    .setPairedAtEpochMs(100L)
                    .setLastSeenEpochMs(200L)
                    .addCapabilities("notify")
                    .build()
            )
            .build()
            .toByteArray()
        storeFile.writeBytes(v1Bytes)

        val store = DataStoreTrustStore(storeFile)
        val records = store.list()

        assertEquals(1, records.size)
        val record = records.single()
        assertEquals("mac-1", record.deviceId)
        assertEquals("aa".repeat(32), record.spkiSha256Hex)
        assertFalse(record.pendingRotation)
    }
}
