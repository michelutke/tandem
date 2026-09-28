package dev.tandem.feature.notifications

import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.testing.FakeElapsedRealtime
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.NotificationPosted
import dev.tandem.protocol.v1.notificationDismiss
import dev.tandem.protocol.v1.notificationPosted
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.time.Duration.Companion.seconds

/**
 * NotificationSink tests (E30-16; `docs/planning/backlog/phase-3.yaml` E30-16's `tdd:` list).
 * [FakeTandemSession] scripts connection state via `emitState` and records sends via `sentFrames`;
 * [FakeElapsedRealtime] ties buffered-entry age to the same `testScheduler` the
 * `StandardTestDispatcher` uses (E00-18).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class NotificationSinkTest {
    @Test
    fun notificationBuffer_disconnected51Posts_holdsNewest50() =
        runTest {
            val session = FakeTandemSession()
            val sink = newSink(session)

            repeat(POSTS_51) { i -> sink.onNotificationPosted(posted("key-$i")) }
            runCurrent()

            session.emitState(ready())
            runCurrent()

            val sentKeys = session.sentFrames.map { it.notificationPosted.key }
            assertEquals((1 until POSTS_51).map { "key-$it" }, sentKeys)
        }

    @Test
    fun notificationBuffer_entryOlderThan60s_evictedBeforeFlush() =
        runTest {
            val session = FakeTandemSession()
            val sink = newSink(session)

            sink.onNotificationPosted(posted("stale"))
            runCurrent()
            advanceTimeBy(61.seconds)
            sink.onNotificationPosted(posted("fresh"))
            runCurrent()

            session.emitState(ready())
            runCurrent()

            assertEquals(listOf("fresh"), session.sentFrames.map { it.notificationPosted.key })
        }

    @Test
    fun notificationBuffer_reconnected_flushesOldestFirstThenEmpty() =
        runTest {
            val session = FakeTandemSession()
            val sink = newSink(session)

            sink.onNotificationPosted(posted("a"))
            sink.onNotificationPosted(posted("b"))
            sink.onNotificationPosted(posted("c"))
            runCurrent()

            session.emitState(ready())
            runCurrent()

            assertEquals(listOf("a", "b", "c"), session.sentFrames.map { it.notificationPosted.key })

            // Buffer empty afterwards: a disconnect-then-reconnect with nothing new sends nothing.
            session.emitState(ConnectionState.Disconnected())
            session.emitState(ready())
            runCurrent()
            assertEquals(listOf("a", "b", "c"), session.sentFrames.map { it.notificationPosted.key })
        }

    @Test
    fun notificationBuffer_bufferedKeyDismissed_neitherPostNorDismissSent() =
        runTest {
            val session = FakeTandemSession()
            val sink = newSink(session)

            sink.onNotificationPosted(posted("dismissed-key"))
            runCurrent()
            sink.onNotificationDismissed(notificationDismiss { key = "dismissed-key" })
            runCurrent()

            session.emitState(ready())
            runCurrent()

            assertTrue(session.sentFrames.isEmpty())
        }

    @Test
    fun notificationBuffer_connected_sendsImmediately() =
        runTest {
            val session = FakeTandemSession()
            val sink = newSink(session)
            session.emitState(ready())
            runCurrent()

            sink.onNotificationPosted(posted("live"))
            runCurrent()

            assertEquals(listOf("live"), session.sentFrames.map { it.notificationPosted.key })
        }

    @Test
    fun notificationBuffer_newInstanceAfterBuffering_startsEmpty() =
        runTest {
            val session = FakeTandemSession()
            val firstSink = newSink(session)
            firstSink.onNotificationPosted(posted("never-flushed"))
            runCurrent()
            firstSink.close()

            // A fresh instance shares no state with a prior one (no disk persistence): it has
            // nothing buffered, so a reconnect it observes sends nothing.
            newSink(session)
            session.emitState(ready())
            runCurrent()

            assertTrue(session.sentFrames.none { it.channel == Channel.CHANNEL_NOTIFY })
        }

    private fun TestScope.newSink(session: FakeTandemSession): NotificationSink =
        NotificationSink(session, FakeElapsedRealtime(testScheduler), StandardTestDispatcher(testScheduler))

    private fun posted(key: String): NotificationPosted =
        notificationPosted {
            this.key = key
            packageName = "com.example.chat"
        }

    private fun ready(): ConnectionState.Ready = ConnectionState.Ready(connectedAt = Instant.EPOCH)

    private companion object {
        const val POSTS_51 = 51
    }
}
