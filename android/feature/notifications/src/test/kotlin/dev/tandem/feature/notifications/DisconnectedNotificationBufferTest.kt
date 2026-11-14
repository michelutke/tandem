package dev.tandem.feature.notifications

import dev.tandem.core.testing.FakeElapsedRealtime
import dev.tandem.protocol.v1.IconData
import dev.tandem.protocol.v1.NotificationDismiss
import dev.tandem.protocol.v1.NotificationPosted
import dev.tandem.protocol.v1.notificationDismiss
import dev.tandem.protocol.v1.notificationPosted
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DisconnectedNotificationBufferTest {
    private val scheduler = TestCoroutineScheduler()
    private val buffer =
        DisconnectedNotificationBuffer(
            FakeElapsedRealtime(scheduler),
            CoroutineScope(StandardTestDispatcher(scheduler)),
        )

    @Test
    fun notificationsFeature_notificationPostedWhileDisconnected_flushedOnNextSessionReady() {
        buffer.onNotificationPosted(post("a"))
        buffer.onNotificationPosted(post("b"))
        val sink = RecordingSink()

        buffer.attach(sink)
        buffer.onNotificationPosted(post("c"))

        assertEquals(listOf("a", "b", "c"), sink.posted)
    }

    @Test
    fun notificationsFeature_bufferedOlderThan60s_notFlushed() {
        buffer.onNotificationPosted(post("old"))
        scheduler.advanceTimeBy(60_000)
        buffer.onNotificationPosted(post("fresh"))
        val sink = RecordingSink()

        buffer.attach(sink)

        assertEquals(listOf("fresh"), sink.posted)
    }

    @Test
    fun notificationsFeature_moreThan50Buffered_oldestDropped() {
        repeat(60) { buffer.onNotificationPosted(post("k$it")) }
        val sink = RecordingSink()

        buffer.attach(sink)

        assertEquals(50, sink.posted.size)
        assertEquals("k10", sink.posted.first())
    }

    @Test
    fun notificationsFeature_dismissOfBufferedKey_neverSent() {
        buffer.onNotificationPosted(post("a"))
        buffer.onNotificationDismissed(notificationDismiss { key = "a" })
        val sink = RecordingSink()

        buffer.attach(sink)

        assertTrue(sink.posted.isEmpty())
        assertTrue(sink.dismissed.isEmpty())
    }

    @Test
    fun notificationsFeature_afterDetach_postsBufferedAgain() {
        val sink = RecordingSink()
        buffer.attach(sink)
        buffer.detach()
        buffer.onNotificationPosted(post("a"))
        val next = RecordingSink()

        buffer.attach(next)

        assertTrue(sink.posted.isEmpty())
        assertEquals(listOf("a"), next.posted)
    }

    @Test
    fun notificationsFeature_clearWhileDisconnected_nothingFlushedToNextSession() {
        buffer.onNotificationPosted(post("a"))

        buffer.clear()
        val sink = RecordingSink()
        buffer.attach(sink)

        assertTrue(sink.posted.isEmpty())
    }

    @Test
    fun notificationsFeature_bufferedPostExpiresWhileDisconnected_evictedByTimerWithoutNewEvent() {
        buffer.onNotificationPosted(post("a"))

        scheduler.advanceTimeBy(60_001)
        scheduler.runCurrent()

        assertEquals(0, buffer.size)
    }

    @Test
    fun notificationsFeature_detachAfterExpiry_evictsExpiredEntries() {
        val idleScope = CoroutineScope(StandardTestDispatcher(TestCoroutineScheduler()))
        val untimed = DisconnectedNotificationBuffer(FakeElapsedRealtime(scheduler), idleScope)
        untimed.onNotificationPosted(post("a"))
        scheduler.advanceTimeBy(60_000)

        untimed.detach()

        assertEquals(0, untimed.size)
    }

    private fun post(key: String) = notificationPosted { this.key = key }

    private class RecordingSink : NotificationEventSink {
        val posted = mutableListOf<String>()
        val dismissed = mutableListOf<String>()

        override fun onNotificationPosted(notification: NotificationPosted) {
            posted += notification.key
        }

        override fun onNotificationDismissed(dismiss: NotificationDismiss) {
            dismissed += dismiss.key
        }

        override fun onIconData(icon: IconData) = Unit
    }
}
