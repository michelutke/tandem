package dev.tandem.app.ring

import dev.tandem.core.protocol.multiplex.MultiplexerClose
import dev.tandem.core.protocol.multiplex.MultiplexerClosedException
import dev.tandem.core.testing.FakeElapsedRealtime
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.protocol.v1.RingStop
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import kotlin.time.Duration.Companion.seconds

// E23-06 tdd:
//   unit: ringController_phoneDismiss_stopsPlaybackAndSendsRingStopFromPhone
//   unit: ringController_macRingStopReceived_stopsPlaybackWithoutEcho
//   unit: ringController_ringWhileAlreadyRinging_noSecondAlarmStart
//   unit: ringController_tenRingsIn10s_alarmStartedAtMostTwice
@OptIn(ExperimentalCoroutinesApi::class)
class RingControllerTest {
    @Test
    fun ringController_phoneDismiss_stopsPlaybackAndSendsRingStopFromPhone() =
        runTest {
            val alarmPlayer = FakeAlarmPlayer()
            val session = FakeTandemSession()
            val controller = ringController(alarmPlayer, session)

            controller.ring()
            controller.dismissedByPhone()

            assertFalse(alarmPlayer.isPlaying)
            assertEquals(1, session.sentFrames.size)
            assertEquals(
                RingStop.Origin.ORIGIN_PHONE,
                session.sentFrames
                    .single()
                    .ringStop.origin,
            )
        }

    @Test
    fun ringController_phoneDismissAfterSessionClosed_stopsPlaybackWithoutThrowing() =
        runTest {
            val alarmPlayer = FakeAlarmPlayer()
            val session = FakeTandemSession()
            session.failNextSend(MultiplexerClosedException(MultiplexerClose.PeerClosed))
            val controller = ringController(alarmPlayer, session)

            controller.ring()
            controller.dismissedByPhone()

            assertFalse(alarmPlayer.isPlaying)
        }

    @Test
    fun ringController_stopWhileNothingRinging_cancelsStaleRingNotification() =
        runTest {
            val notifier = FakeRingNotifier()
            val controller = ringController(FakeAlarmPlayer(), FakeTandemSession(), notifier = notifier)

            controller.dismissedByPhone()

            assertEquals(1, notifier.cancelled)
        }

    @Test
    fun ringController_ringStartsAlarm_reportsStartedOnlyOnce() =
        runTest {
            val controller = ringController(FakeAlarmPlayer(), FakeTandemSession())

            assertTrue(controller.ring())
            assertFalse(controller.ring())
        }

    @Test
    fun ringController_macRingStopReceived_stopsPlaybackWithoutEcho() =
        runTest {
            val alarmPlayer = FakeAlarmPlayer()
            val session = FakeTandemSession()
            val controller = ringController(alarmPlayer, session)

            controller.ring()
            controller.ringStopReceived()

            assertFalse(alarmPlayer.isPlaying)
            assertTrue(session.sentFrames.isEmpty())
        }

    @Test
    fun ringController_ringWhileAlreadyRinging_noSecondAlarmStart() =
        runTest {
            val alarmPlayer = FakeAlarmPlayer()
            val controller = ringController(alarmPlayer, FakeTandemSession())

            controller.ring()
            controller.ring()

            assertEquals(1, alarmPlayer.startCount)
            assertTrue(alarmPlayer.isPlaying)
        }

    @Test
    fun ringController_tenRingsIn10s_alarmStartedAtMostTwice() =
        runTest {
            val alarmPlayer = FakeAlarmPlayer()
            val controller = ringController(alarmPlayer, FakeTandemSession(), FakeElapsedRealtime(testScheduler))

            repeat(10) {
                controller.ring()
                controller.ringStopReceived()
                advanceTimeBy(1.seconds)
            }

            assertEquals(2, alarmPlayer.startCount)
        }

    @Test
    fun ringController_ringReceived_showsStopNotificationUntilStopped() =
        runTest {
            val notifier = FakeRingNotifier()
            val controller = ringController(FakeAlarmPlayer(), FakeTandemSession(), notifier = notifier)

            controller.ring()
            assertEquals(1, notifier.shown)
            controller.ringStopReceived()

            assertEquals(1, notifier.cancelled)
        }

    @Test
    fun ringController_ringExceedsMaxDuration_stopsAlarmAndRestoresVolume() =
        runTest {
            val alarmPlayer = FakeAlarmPlayer()
            val notifier = FakeRingNotifier()
            val session = FakeTandemSession()
            val controller = ringController(alarmPlayer, session, notifier = notifier)

            controller.ring()
            advanceTimeBy(RingController.MAX_RING_DURATION - 1.seconds)
            assertTrue(alarmPlayer.isPlaying)
            advanceTimeBy(2.seconds)
            runCurrent()

            assertFalse(alarmPlayer.isPlaying)
            assertEquals(FakeAlarmPlayer.INITIAL_VOLUME, alarmPlayer.alarmVolume)
            assertEquals(1, notifier.cancelled)
            assertEquals(
                RingStop.Origin.ORIGIN_PHONE,
                session.sentFrames
                    .single()
                    .ringStop.origin,
            )
        }

    @Test
    fun ringController_stoppedBeforeMaxDuration_timeoutDoesNotStopLaterRing() =
        runTest {
            val alarmPlayer = FakeAlarmPlayer()
            val controller = ringController(alarmPlayer, FakeTandemSession())

            controller.ring()
            controller.ringStopReceived()
            advanceTimeBy(11.seconds)
            controller.ring()
            advanceTimeBy(RingController.MAX_RING_DURATION - 5.seconds)

            assertTrue(alarmPlayer.isPlaying)
        }

    private fun TestScope.ringController(
        alarmPlayer: FakeAlarmPlayer,
        session: FakeTandemSession,
        elapsedRealtimeSource: ElapsedRealtimeSource = FakeElapsedRealtime(testScheduler),
        notifier: RingNotifier = FakeRingNotifier(),
    ) = RingController(
        ringHandler =
            RingHandler(
                alarmPlayer = alarmPlayer,
                notificationPolicyAccess =
                    FakeNotificationPolicyAccess(access = true, initialFilter = InterruptionFilter.ALL),
            ),
        session = session,
        elapsedRealtimeSource = elapsedRealtimeSource,
        ringNotifier = notifier,
        scope = backgroundScope,
    )
}

class FakeRingNotifier : RingNotifier {
    var shown = 0
        private set
    var cancelled = 0
        private set

    override fun show() {
        shown++
    }

    override fun cancel() {
        cancelled++
    }
}
