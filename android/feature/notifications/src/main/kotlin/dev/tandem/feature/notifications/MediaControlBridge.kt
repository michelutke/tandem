package dev.tandem.feature.notifications

import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.CapabilityUnavailable
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.NowPlaying
import dev.tandem.protocol.v1.PlaybackState
import dev.tandem.protocol.v1.capabilityUnavailable
import dev.tandem.protocol.v1.nowPlaying
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch

private const val TITLE_MAX_CHARS = 256
private const val ARTIST_MAX_CHARS = 128
private const val ALBUM_MAX_CHARS = 128

/**
 * E72-02 (F-10.1, docs/protocol/SPEC.md #media-control): pushes the active media session's
 * metadata to the Mac as `NowPlaying` and dispatches the Mac's `PlayPause`/`Next`/`Previous`/`Stop`
 * to the session's transport controls through [gateway]. Without notification-listener access
 * nothing is read or dispatched and the Mac is told `CapabilityUnavailable`. Track text is never
 * logged.
 */
class MediaControlBridge(
    private val session: TandemSession,
    private val gateway: MediaSessionGateway,
) {
    /** Bridges [gateway] and [session]'s STATUS channel until cancelled. */
    suspend fun run() {
        if (!gateway.hasListenerAccess()) {
            session.send(Channel.CHANNEL_STATUS) {
                capabilityUnavailable =
                    capabilityUnavailable { feature = CapabilityUnavailable.Feature.FEATURE_MEDIA_CONTROL }
            }
            return
        }
        coroutineScope {
            launch { session.receive(Channel.CHANNEL_STATUS).collect(::dispatch) }
            gateway.sessionChanges().publishDistinct()
        }
    }

    private suspend fun Flow<MediaSessionSnapshot?>.publishDistinct() {
        filterNotNull().distinctUntilChanged().collect { snapshot ->
            session.send(Channel.CHANNEL_STATUS) { nowPlaying = snapshot.toNowPlaying() }
        }
    }

    private fun dispatch(envelope: Envelope) {
        when {
            envelope.hasPlayPause() -> togglePlayPause()
            envelope.hasNext() -> gateway.next()
            envelope.hasPrevious() -> gateway.previous()
            envelope.hasStop() -> gateway.stop()
        }
    }

    private fun togglePlayPause() {
        when (gateway.currentSession()?.state) {
            null -> Unit
            MediaPlaybackState.PLAYING -> gateway.pause()
            MediaPlaybackState.PAUSED, MediaPlaybackState.STOPPED -> gateway.play()
        }
    }
}

private fun MediaSessionSnapshot.toNowPlaying(): NowPlaying {
    val snapshot = this
    return nowPlaying {
        title = snapshot.title.truncated(TITLE_MAX_CHARS)
        artist = snapshot.artist.truncated(ARTIST_MAX_CHARS)
        state =
            when (snapshot.state) {
                MediaPlaybackState.PLAYING -> PlaybackState.PLAYBACK_STATE_PLAYING
                MediaPlaybackState.PAUSED -> PlaybackState.PLAYBACK_STATE_PAUSED
                MediaPlaybackState.STOPPED -> PlaybackState.PLAYBACK_STATE_STOPPED
            }
        snapshot.album?.let { album = it.truncated(ALBUM_MAX_CHARS) }
        snapshot.durationMs?.let { durationMs = it }
    }
}

private fun String.truncated(maxChars: Int): String {
    if (length <= maxChars) return this
    val end = if (this[maxChars - 1].isHighSurrogate()) maxChars - 1 else maxChars
    return substring(0, end)
}
