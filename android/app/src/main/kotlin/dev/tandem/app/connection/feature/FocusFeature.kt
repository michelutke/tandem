package dev.tandem.app.connection.feature

import dev.tandem.app.connection.SessionFeature
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.transport.TandemSession
import dev.tandem.feature.notifications.FocusSyncReceiver
import dev.tandem.feature.notifications.InterruptionFilterGateway

/** Applies the Mac's Focus state to this phone's interruption filter (F-10.2). */
class FocusFeature(
    private val gateway: () -> InterruptionFilterGateway,
) : SessionFeature {
    override suspend fun run(
        session: TandemSession,
        peer: SpkiFingerprint,
        peerSpkiDer: ByteArray?,
    ) {
        FocusSyncReceiver(session, gateway()).run()
    }
}
