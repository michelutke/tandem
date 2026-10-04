package dev.tandem.app.connection.feature

import dev.tandem.app.connection.SessionFeature
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.storage.rotation.RotationEventLog
import dev.tandem.core.storage.rotation.RotationPinStore
import dev.tandem.core.storage.rotation.RotationReceiver
import dev.tandem.core.transport.TandemSession
import java.security.SecureRandom
import java.time.Clock

/** Receives the Mac's `KeyRotation` on the session's CONTROL channel (E70-04, F-1.x key rotation). */
class RotationFeature(
    private val pins: RotationPinStore,
    private val clock: Clock,
    private val random: SecureRandom,
    private val eventLog: RotationEventLog,
) : SessionFeature {
    override suspend fun run(
        session: TandemSession,
        peer: SpkiFingerprint,
        peerSpkiDer: ByteArray?,
    ) {
        RotationReceiver(session, peerSpkiDer, pins, clock, random, eventLog).run()
    }
}
