package dev.tandem.feature.notifications

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow

/**
 * Recording fake for [MediaSessionGateway] (E72-02): models listener access and the active session
 * as plain state, lets a test push session changes through [emitSession], and records every
 * transport call in [commands].
 */
class FakeMediaSessionGateway(
    private val access: Boolean,
    var session: MediaSessionSnapshot? = null,
) : MediaSessionGateway {
    private val changes = MutableSharedFlow<MediaSessionSnapshot?>(extraBufferCapacity = 16)

    val commands = mutableListOf<String>()

    override fun hasListenerAccess(): Boolean = access

    override fun currentSession(): MediaSessionSnapshot? = session

    override fun sessionChanges(): Flow<MediaSessionSnapshot?> = changes

    suspend fun emitSession(snapshot: MediaSessionSnapshot?) {
        session = snapshot
        changes.emit(snapshot)
    }

    override fun play() {
        record("play")
    }

    override fun pause() {
        record("pause")
    }

    override fun next() {
        record("next")
    }

    override fun previous() {
        record("previous")
    }

    override fun stop() {
        record("stop")
    }

    private fun record(command: String) {
        if (session != null) commands += command
    }
}
