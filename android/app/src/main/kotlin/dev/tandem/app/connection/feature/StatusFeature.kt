package dev.tandem.app.connection.feature

import dev.tandem.app.connection.SessionFeature
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.transport.TandemSession
import dev.tandem.feature.status.StatusAggregator
import dev.tandem.feature.status.StatusPublisher
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.awaitCancellation
import java.time.Clock

/** Publishes the phone's battery/network/signal status on the STATUS channel (F-4.3). */
class StatusFeature(
    private val aggregator: StatusAggregator,
    private val clock: Clock,
    private val dispatcher: CoroutineDispatcher,
) : SessionFeature {
    override suspend fun run(
        session: TandemSession,
        peer: SpkiFingerprint,
        peerSpkiDer: ByteArray?,
    ) {
        val publisher = StatusPublisher(aggregator.status, session, clock, dispatcher)
        try {
            awaitCancellation()
        } finally {
            publisher.close()
        }
    }
}
