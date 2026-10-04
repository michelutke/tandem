package dev.tandem.app.connection

import dev.tandem.app.service.RegisteredSession
import dev.tandem.core.protocol.connection.ConnectionState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/**
 * Runs every [SessionFeature] against a registered session (E20-23) and returns only after the
 * session has closed and every feature has finished detaching, so a reconnect can never overlap
 * the previous session's consumers. A failing feature is logged by class name only (invariant 7)
 * and never takes the other features down.
 */
class FeatureAttacher(
    private val features: List<SessionFeature>,
    private val logFailure: (Throwable) -> Unit,
) {
    suspend fun attach(registered: RegisteredSession) {
        coroutineScope {
            val jobs = features.map { feature -> launch { runGuarded(feature, registered) } }
            registered.session.state.first { it is ConnectionState.Disconnected || it is ConnectionState.Failed }
            jobs.forEach { it.cancel() }
        }
    }

    @Suppress("TooGenericExceptionCaught") // one failing feature must not detach the others
    private suspend fun runGuarded(
        feature: SessionFeature,
        registered: RegisteredSession,
    ) {
        try {
            feature.run(registered.session, registered.peer, registered.peerSpkiDer)
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (e: Exception) {
            logFailure(e)
        }
    }
}
