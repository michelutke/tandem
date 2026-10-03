package dev.tandem.feature.notifications

import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.CapabilityUnavailable
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.EnvelopeKt
import dev.tandem.protocol.v1.PlaybackState
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.next
import dev.tandem.protocol.v1.playPause
import dev.tandem.protocol.v1.previous
import dev.tandem.protocol.v1.stop
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * MediaControlBridge tests (E72-02; `docs/planning/backlog/phase-7.yaml` E72-02's `tdd:` list).
 * [FakeTandemSession] scripts incoming transport commands and records the NowPlaying and
 * CapabilityUnavailable frames; [FakeMediaSessionGateway] stands in for `MediaSessionManager`.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class MediaControlBridgeTest {
    @Test
    fun mediaControlBridge_playPauseWhilePlaying_callsTransportPause() =
        runTest {
            val gateway = FakeMediaSessionGateway(access = true, session = snapshot(MediaPlaybackState.PLAYING))
            val session = startBridge(gateway)

            session.emitCommand { playPause = playPause {} }
            runCurrent()

            assertEquals(listOf("pause"), gateway.commands)
        }

    @Test
    fun mediaControlBridge_playPauseWhilePaused_callsTransportPlay() =
        runTest {
            val gateway = FakeMediaSessionGateway(access = true, session = snapshot(MediaPlaybackState.PAUSED))
            val session = startBridge(gateway)

            session.emitCommand { playPause = playPause {} }
            runCurrent()

            assertEquals(listOf("play"), gateway.commands)
        }

    @Test
    fun mediaControlBridge_nextPreviousStop_dispatchedToTransport() =
        runTest {
            val gateway = FakeMediaSessionGateway(access = true, session = snapshot(MediaPlaybackState.PLAYING))
            val session = startBridge(gateway)

            session.emitCommand { next = next {} }
            session.emitCommand { previous = previous {} }
            session.emitCommand { stop = stop {} }
            runCurrent()

            assertEquals(listOf("next", "previous", "stop"), gateway.commands)
        }

    @Test
    fun mediaControlBridge_commandWithoutActiveSession_dropped() =
        runTest {
            val gateway = FakeMediaSessionGateway(access = true, session = null)
            val session = startBridge(gateway)

            session.emitCommand { playPause = playPause {} }
            session.emitCommand { next = next {} }
            runCurrent()

            assertTrue(gateway.commands.isEmpty())
        }

    @Test
    fun mediaControlBridge_metadataChanged_sendsNowPlayingWithTitleArtist() =
        runTest {
            val gateway = FakeMediaSessionGateway(access = true)
            val session = startBridge(gateway)

            gateway.emitSession(
                MediaSessionSnapshot(
                    title = "So What",
                    artist = "Miles Davis",
                    album = "Kind of Blue",
                    durationMs = 562_000,
                    state = MediaPlaybackState.PLAYING,
                ),
            )
            runCurrent()

            val frame = session.sentFrames.single()
            assertEquals(Channel.CHANNEL_STATUS, frame.channel)
            assertTrue(frame.hasNowPlaying())
            assertEquals("So What", frame.nowPlaying.title)
            assertEquals("Miles Davis", frame.nowPlaying.artist)
            assertEquals(PlaybackState.PLAYBACK_STATE_PLAYING, frame.nowPlaying.state)
            assertEquals("Kind of Blue", frame.nowPlaying.album)
            assertEquals(562_000L, frame.nowPlaying.durationMs)
        }

    @Test
    fun mediaControlBridge_unchangedSession_sendsNowPlayingOnce() =
        runTest {
            val gateway = FakeMediaSessionGateway(access = true)
            val session = startBridge(gateway)

            gateway.emitSession(snapshot(MediaPlaybackState.PLAYING))
            gateway.emitSession(snapshot(MediaPlaybackState.PLAYING))
            gateway.emitSession(snapshot(MediaPlaybackState.PAUSED))
            runCurrent()

            assertEquals(
                listOf(PlaybackState.PLAYBACK_STATE_PLAYING, PlaybackState.PLAYBACK_STATE_PAUSED),
                session.sentFrames.map { it.nowPlaying.state },
            )
        }

    @Test
    fun mediaControlBridge_noActiveSession_sendsNothing() =
        runTest {
            val gateway = FakeMediaSessionGateway(access = true)
            val session = startBridge(gateway)

            gateway.emitSession(null)
            runCurrent()

            assertTrue(session.sentFrames.isEmpty())
        }

    @Test
    fun mediaControlBridge_overlongStrings_truncatedToCaps() =
        runTest {
            val gateway = FakeMediaSessionGateway(access = true)
            val session = startBridge(gateway)

            gateway.emitSession(
                MediaSessionSnapshot(
                    title = "t".repeat(300),
                    artist = "a".repeat(200),
                    album = "b".repeat(200),
                    durationMs = null,
                    state = MediaPlaybackState.PLAYING,
                ),
            )
            runCurrent()

            val nowPlaying = session.sentFrames.single().nowPlaying
            assertEquals(256, nowPlaying.title.length)
            assertEquals(128, nowPlaying.artist.length)
            assertEquals(128, nowPlaying.album.length)
            assertFalse(nowPlaying.hasDurationMs())
        }

    @Test
    fun mediaControlBridge_listenerAccessRevoked_sendsCapabilityUnavailable() =
        runTest {
            val gateway = FakeMediaSessionGateway(access = false, session = snapshot(MediaPlaybackState.PLAYING))
            val session = startBridge(gateway)

            gateway.emitSession(snapshot(MediaPlaybackState.PAUSED))
            session.emitCommand { playPause = playPause {} }
            runCurrent()

            val frame = session.sentFrames.single()
            assertEquals(Channel.CHANNEL_STATUS, frame.channel)
            assertTrue(frame.hasCapabilityUnavailable())
            assertEquals(CapabilityUnavailable.Feature.FEATURE_MEDIA_CONTROL, frame.capabilityUnavailable.feature)
            assertTrue(gateway.commands.isEmpty())
        }

    private fun snapshot(state: MediaPlaybackState) =
        MediaSessionSnapshot(
            title = "Blue in Green",
            artist = "Miles Davis",
            album = null,
            durationMs = null,
            state = state,
        )

    private fun TestScope.startBridge(gateway: MediaSessionGateway): FakeTandemSession {
        val session = FakeTandemSession()
        backgroundScope.launch { MediaControlBridge(session, gateway).run() }
        runCurrent()
        return session
    }

    private fun FakeTandemSession.emitCommand(payload: EnvelopeKt.Dsl.() -> Unit) {
        emitIncoming(
            envelope {
                channel = Channel.CHANNEL_STATUS
                payload()
            },
        )
    }
}
