package dev.tandem.core.transport.media

import com.google.protobuf.ByteString
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.ByteStream
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.reconnect.CandidateAddress
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Ties the single media connection to its control [session] (E60-09; SPEC.md #media-ticket; macOS
 * twin `MediaSessionRegistry`, E60-04): the media connection is closed as soon as the control
 * session's `state` leaves the connected lifecycle (`Disconnected` or `Failed`), and a new [start]
 * closes the prior media connection before dialing. It only ever closes the media stream: a media
 * failure never touches the control session (SPEC.md #media-ticket). [mirrorActive] reports
 * whether a media connection is currently open.
 */
class MediaConnectionLifecycle(
    private val session: TandemSession,
    private val dialer: MediaDialer,
    private val scope: CoroutineScope,
) {
    private class Active(
        val stream: ByteStream,
        val watcher: Job,
    )

    private val startLock = Mutex()
    private var active: Active? = null
    private val mutableMirrorActive = MutableStateFlow(false)

    val mirrorActive: StateFlow<Boolean> = mutableMirrorActive.asStateFlow()

    /** Closes any active media connection, then dials; the new connection is tracked on success. */
    suspend fun start(
        address: CandidateAddress,
        mirrorSessionId: ByteString,
    ): MediaDialResult =
        startLock.withLock {
            closeActive()
            val result = dialer.dial(address, mirrorSessionId)
            if (result is MediaDialResult.Connected) adopt(result.stream)
            result
        }

    /** Closes the active media connection, if any. */
    suspend fun stop() = startLock.withLock { closeActive() }

    private fun adopt(stream: ByteStream) {
        val watcher =
            scope.launch {
                session.state.first { it.isTerminal() }
                closeIfCurrent(stream)
            }
        active = Active(stream, watcher)
        mutableMirrorActive.value = true
    }

    private fun closeIfCurrent(stream: ByteStream) {
        if (active?.stream !== stream) return
        active = null
        mutableMirrorActive.value = false
        stream.closeAbruptly()
    }

    private fun closeActive() {
        val current = active ?: return
        active = null
        current.watcher.cancel()
        mutableMirrorActive.value = false
        current.stream.closeAbruptly()
    }

    private fun ConnectionState.isTerminal(): Boolean =
        this is ConnectionState.Disconnected || this is ConnectionState.Failed
}
