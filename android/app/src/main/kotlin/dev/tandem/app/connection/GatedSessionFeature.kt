package dev.tandem.app.connection

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.transport.TandemSession
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged

/**
 * Runs [feature] only while [enabled] is true: turning it off cancels the attached feature (which
 * releases everything it started) and turning it back on re-attaches it, all within the same session.
 */
class GatedSessionFeature(
    private val feature: SessionFeature,
    private val enabled: Flow<Boolean>,
) : SessionFeature {
    override suspend fun run(
        session: TandemSession,
        peer: SpkiFingerprint,
        peerSpkiDer: ByteArray?,
    ) {
        enabled.distinctUntilChanged().collectLatest { on ->
            if (on) feature.run(session, peer, peerSpkiDer)
        }
    }
}
