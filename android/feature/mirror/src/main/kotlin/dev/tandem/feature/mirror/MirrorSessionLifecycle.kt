package dev.tandem.feature.mirror

import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.TandemSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean

/** The phone-side mirror indicator (ongoing notification, invariant 8) is told when capture has ended. */
fun interface MirrorIndicator {
    fun onMirrorStopped()
}

/**
 * Ties one mirror's [pipeline] to its end conditions (E61-11): user [stop], system MediaProjection
 * revocation (via the capture's stop listener), control-session end and a media connection drop
 * all release encoder, VirtualDisplay, MediaProjection and the media stream once, then notify
 * [indicator] once.
 */
class MirrorSessionLifecycle(
    private val pipeline: EncodePipeline,
    private val session: TandemSession,
    private val indicator: MirrorIndicator,
    private val scope: CoroutineScope,
) {
    private val stopped = AtomicBoolean(false)

    @Volatile
    private var sessionWatcher: Job? = null

    fun start() {
        sessionWatcher =
            scope.launch {
                session.state.first { it is ConnectionState.Disconnected || it is ConnectionState.Failed }
                stop()
            }
        scope.launch {
            try {
                pipeline.run()
            } catch (_: IOException) {
                // media connection dropped; released below
            } finally {
                stop()
            }
        }
    }

    /** Idempotent. */
    fun stop() {
        if (!stopped.compareAndSet(false, true)) return
        sessionWatcher?.cancel()
        try {
            pipeline.stop()
        } finally {
            indicator.onMirrorStopped()
        }
    }
}
