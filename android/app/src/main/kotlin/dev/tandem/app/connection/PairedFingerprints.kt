package dev.tandem.app.connection

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.storage.trust.PENDING_MAX_AGE_MS
import dev.tandem.core.storage.trust.PeerRecord
import dev.tandem.core.storage.trust.TrustStore
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import java.time.Clock
import java.util.Base64

/**
 * SPKI fingerprints of every paired Mac in [trustStore] (E20-23, E70-14): [load] reads them at dial
 * time for the pinning trust manager; [snapshot] is the synchronous view discovery matching needs,
 * kept current from [TrustStore.observeList]. Each record contributes its primary pin plus an
 * unexpired grace pin and an unexpired pending pin ([acceptedPins]). The trust store is the only
 * source (invariant 3).
 */
class PairedFingerprints(
    private val trustStore: TrustStore,
    private val clock: Clock,
    dispatcher: CoroutineDispatcher,
) {
    @Volatile
    private var latest: List<PeerRecord> = emptyList()

    init {
        trustStore
            .observeList()
            .onEach { records -> latest = records }
            .launchIn(CoroutineScope(SupervisorJob() + dispatcher))
    }

    fun snapshot(): List<SpkiFingerprint> = latest.flatMap { it.acceptedPins(nowEpochMs()) }

    suspend fun load(): List<SpkiFingerprint> = trustStore.list().flatMap { it.acceptedPins(nowEpochMs()) }

    private fun nowEpochMs(): Long = clock.instant().toEpochMilli()
}

internal fun PeerRecord.acceptedPins(nowEpochMs: Long): List<SpkiFingerprint> =
    listOfNotNull(
        spkiSha256Base64Url,
        graceSpkiSha256Base64Url?.takeIf { (graceExpiresAtEpochMs ?: 0L) > nowEpochMs },
        pendingSpkiSha256Base64Url?.takeIf { (pendingSinceEpochMs ?: 0L) > nowEpochMs - PENDING_MAX_AGE_MS },
    ).mapNotNull(::decodePin)

private fun decodePin(base64Url: String): SpkiFingerprint? =
    try {
        SpkiFingerprint(Base64.getUrlDecoder().decode(base64Url))
    } catch (_: IllegalArgumentException) {
        null
    }
