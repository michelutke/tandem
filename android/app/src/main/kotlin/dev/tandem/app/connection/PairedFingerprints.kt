package dev.tandem.app.connection

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.storage.trust.PeerRecord
import dev.tandem.core.storage.trust.TrustStore
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import java.util.Base64

/**
 * SPKI fingerprints of every paired Mac in [trustStore] (E20-23): [load] reads them at dial time
 * for the pinning trust manager; [snapshot] is the synchronous view discovery matching needs,
 * kept current from [TrustStore.observeList]. The trust store is the only source (invariant 3).
 */
class PairedFingerprints(
    private val trustStore: TrustStore,
    dispatcher: CoroutineDispatcher,
) {
    @Volatile
    private var latest: List<SpkiFingerprint> = emptyList()

    init {
        trustStore
            .observeList()
            .onEach { records -> latest = records.mapNotNull(::toFingerprint) }
            .launchIn(CoroutineScope(SupervisorJob() + dispatcher))
    }

    fun snapshot(): List<SpkiFingerprint> = latest

    suspend fun load(): List<SpkiFingerprint> = trustStore.list().mapNotNull(::toFingerprint)

    private fun toFingerprint(record: PeerRecord): SpkiFingerprint? =
        try {
            SpkiFingerprint(Base64.getUrlDecoder().decode(record.spkiSha256Base64Url))
        } catch (_: IllegalArgumentException) {
            null
        }
}
