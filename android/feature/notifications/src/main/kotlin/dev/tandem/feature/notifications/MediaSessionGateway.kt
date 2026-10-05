package dev.tandem.feature.notifications

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import androidx.core.app.NotificationManagerCompat
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

enum class MediaPlaybackState {
    PLAYING,
    PAUSED,
    STOPPED,
}

/** What the Mac is told about the active media session (E72-02, F-10.1). */
data class MediaSessionSnapshot(
    val title: String,
    val artist: String,
    val album: String?,
    val durationMs: Long?,
    val state: MediaPlaybackState,
)

/**
 * Seam over `MediaSessionManager`/`MediaController` (E72-02, F-10.1), so [MediaControlBridge]
 * stays plain unit-tested against a fake (CLAUDE.md's Robolectric rule). Transport calls act on the
 * active session and do nothing without one. [SystemMediaSessionGateway] is the only production
 * implementation.
 */
interface MediaSessionGateway {
    fun hasListenerAccess(): Boolean

    fun currentSession(): MediaSessionSnapshot?

    /** Emits the active session on collection, then again on every session, metadata or state change. */
    fun sessionChanges(): Flow<MediaSessionSnapshot?>

    fun play()

    fun pause()

    fun next()

    fun previous()

    fun stop()
}

/**
 * Production implementation backed by the real `MediaSessionManager`. Reading active sessions
 * requires notification-listener access for [listenerComponent].
 */
class SystemMediaSessionGateway(
    private val context: Context,
    private val listenerComponent: ComponentName,
) : MediaSessionGateway {
    private val sessionManager = context.getSystemService(MediaSessionManager::class.java)

    override fun hasListenerAccess(): Boolean =
        NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)

    override fun currentSession(): MediaSessionSnapshot? = activeController()?.toSnapshot()

    override fun sessionChanges(): Flow<MediaSessionSnapshot?> =
        callbackFlow {
            var watched: MediaController? = null
            val controllerCallback =
                object : MediaController.Callback() {
                    override fun onMetadataChanged(metadata: MediaMetadata?) {
                        trySend(watched?.toSnapshot())
                    }

                    override fun onPlaybackStateChanged(state: PlaybackState?) {
                        trySend(watched?.toSnapshot())
                    }
                }

            fun watch(controller: MediaController?) {
                watched?.unregisterCallback(controllerCallback)
                watched = controller
                controller?.registerCallback(controllerCallback)
                trySend(controller?.toSnapshot())
            }

            val sessionsListener =
                MediaSessionManager.OnActiveSessionsChangedListener { controllers -> watch(controllers?.firstOrNull()) }
            sessionManager.addOnActiveSessionsChangedListener(sessionsListener, listenerComponent)
            watch(activeController())
            awaitClose {
                sessionManager.removeOnActiveSessionsChangedListener(sessionsListener)
                watched?.unregisterCallback(controllerCallback)
            }
        }

    override fun play() {
        activeController()?.transportControls?.play()
    }

    override fun pause() {
        activeController()?.transportControls?.pause()
    }

    override fun next() {
        activeController()?.transportControls?.skipToNext()
    }

    override fun previous() {
        activeController()?.transportControls?.skipToPrevious()
    }

    override fun stop() {
        activeController()?.transportControls?.stop()
    }

    private fun activeController(): MediaController? = sessionManager.getActiveSessions(listenerComponent).firstOrNull()
}

private fun MediaController.toSnapshot(): MediaSessionSnapshot? {
    val metadata = metadata ?: return null
    return MediaSessionSnapshot(
        title = metadata.getString(MediaMetadata.METADATA_KEY_TITLE).orEmpty(),
        artist = metadata.getString(MediaMetadata.METADATA_KEY_ARTIST).orEmpty(),
        album = metadata.getString(MediaMetadata.METADATA_KEY_ALBUM),
        durationMs = metadata.getLong(MediaMetadata.METADATA_KEY_DURATION).takeIf { it > 0 },
        state =
            when (playbackState?.state) {
                PlaybackState.STATE_PLAYING -> MediaPlaybackState.PLAYING
                PlaybackState.STATE_PAUSED -> MediaPlaybackState.PAUSED
                else -> MediaPlaybackState.STOPPED
            },
    )
}
