package dev.tandem.spike.trust.datastore

import androidx.datastore.core.DataStore
import androidx.datastore.core.DataStoreFactory
import dev.tandem.spike.trust.datastore.proto.PeerRecordProto
import dev.tandem.spike.trust.datastore.proto.TrustStore
import java.io.File
import kotlinx.coroutines.flow.first

/**
 * Prototype trust store on top of Proto DataStore. Keyed by [PeerRecord.spkiSha256Hex] only
 * (invariant 3 -- CLAUDE.md); deviceId is a display field.
 */
class DataStoreTrustStore(file: File) {
    private val store: DataStore<TrustStore> =
        DataStoreFactory.create(serializer = TrustStoreSerializer, produceFile = { file })

    suspend fun put(record: PeerRecord) {
        store.updateData { current ->
            val withoutExisting =
                current.recordsList.filterNot { it.spkiSha256Hex == record.spkiSha256Hex }
            current.toBuilder()
                .clearRecords()
                .addAllRecords(withoutExisting)
                .addRecords(record.toProto())
                .build()
        }
    }

    suspend fun get(spkiSha256Hex: String): PeerRecord? =
        store.data.first().recordsList.firstOrNull { it.spkiSha256Hex == spkiSha256Hex }?.toDomain()

    suspend fun list(): List<PeerRecord> = store.data.first().recordsList.map { it.toDomain() }

    /** Deletes [spkiSha256Hex] atomically; returns once the update transaction has committed. */
    suspend fun delete(spkiSha256Hex: String) {
        store.updateData { current ->
            current.toBuilder()
                .clearRecords()
                .addAllRecords(current.recordsList.filterNot { it.spkiSha256Hex == spkiSha256Hex })
                .build()
        }
    }

    /**
     * Atomic pin swap for key rotation (D-34/E70): replaces [oldSpkiSha256Hex]'s record with
     * [newRecord] in a single `updateData` transaction, so a reader never observes both, or
     * neither, fingerprint.
     */
    suspend fun swapPin(oldSpkiSha256Hex: String, newRecord: PeerRecord) {
        store.updateData { current ->
            val withoutOld = current.recordsList.filterNot { it.spkiSha256Hex == oldSpkiSha256Hex }
            current.toBuilder()
                .clearRecords()
                .addAllRecords(withoutOld)
                .addRecords(newRecord.toProto())
                .build()
        }
    }
}

private fun PeerRecord.toProto(): PeerRecordProto =
    PeerRecordProto.newBuilder()
        .setDeviceId(deviceId)
        .setDisplayName(displayName)
        .setSpkiSha256Hex(spkiSha256Hex)
        .setPairedAtEpochMs(pairedAtEpochMs)
        .setLastSeenEpochMs(lastSeenEpochMs)
        .addAllCapabilities(capabilities)
        .setPendingRotation(pendingRotation)
        .build()

private fun PeerRecordProto.toDomain(): PeerRecord =
    PeerRecord(
        deviceId = deviceId,
        displayName = displayName,
        spkiSha256Hex = spkiSha256Hex,
        pairedAtEpochMs = pairedAtEpochMs,
        lastSeenEpochMs = lastSeenEpochMs,
        capabilities = capabilitiesList,
        pendingRotation = pendingRotation,
    )
