package dev.tandem.app.ring

import dev.tandem.core.testing.FakeElapsedRealtime
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.protocol.v1.RingStop
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.advanceTimeBy
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

    private fun ringController(
        alarmPlayer: FakeAlarmPlayer,
        session: FakeTandemSession,
        elapsedRealtimeSource: ElapsedRealtimeSource = FakeElapsedRealtime(TestCoroutineScheduler()),
    ) = RingController(
        ringHandler =
            RingHandler(
                alarmPlayer = alarmPlayer,
                notificationPolicyAccess =
                    FakeNotificationPolicyAccess(access = true, initialFilter = InterruptionFilter.ALL),
            ),
        session = session,
        elapsedRealtimeSource = elapsedRealtimeSource,
    )
}
