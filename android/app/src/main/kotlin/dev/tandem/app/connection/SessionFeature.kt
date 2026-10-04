package dev.tandem.app.connection

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.transport.TandemSession

/**
 * One feature consumer of a Ready session (E20-23). [run] attaches it, suspends for as long as it
 * is attached and releases everything it started in a `finally` when cancelled: [FeatureAttacher]
 * cancels it the moment the session closes. Consumers subscribe through `session.receive` only.
 */
fun interface SessionFeature {
    suspend fun run(
        session: TandemSession,
        peer: SpkiFingerprint,
    )
}
