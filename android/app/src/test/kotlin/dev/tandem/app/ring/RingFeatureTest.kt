package dev.tandem.app.ring

import dev.tandem.app.connection.feature.RingFeature
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.testing.FakeElapsedRealtime
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.ring
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class RingFeatureTest {
    private val alarmPlayer = FakeAlarmPlayer()
    private val notifier = FakeRingNotifier()
    private val session = FakeTandemSession()

    @Test
    fun ringFeature_sessionStarts_restoresStaleAlarmVolume() =
        runTest {
            val job = startFeature()

            assertEquals(1, alarmPlayer.staleRestoreCount)
            job.cancel()
        }

    @Test
    fun ringFeature_ringReceived_showsStopNotification() =
        runTest {
            val job = startFeature()

            session.emitIncoming(ringEnvelope())
            runCurrent()

            assertEquals(1, notifier.shown)
            job.cancel()
        }

    @Test
    fun ringFeature_sessionEndsWhileRinging_stopsAlarmAndCancelsNotification() =
        runTest {
            val job = startFeature()
            session.emitIncoming(ringEnvelope())
            runCurrent()

            job.cancel()
            runCurrent()

            assertFalse(alarmPlayer.isPlaying)
            assertEquals(1, notifier.cancelled)
        }

    @Test
    fun ringFeature_ringLongerThanMaxDuration_alarmStopped() =
        runTest {
            val job = startFeature()
            session.emitIncoming(ringEnvelope())
            runCurrent()
            assertTrue(alarmPlayer.isPlaying)

            advanceTimeBy(RingController.MAX_RING_DURATION + kotlin.time.Duration.parse("1s"))
            runCurrent()

            assertFalse(alarmPlayer.isPlaying)
            job.cancel()
        }

    private fun kotlinx.coroutines.test.TestScope.startFeature() =
        backgroundScope
            .launch {
                RingFeature(
                    alarmPlayer = { alarmPlayer },
                    policyAccess = {
                        FakeNotificationPolicyAccess(
                            access = true,
                            initialFilter = InterruptionFilter.ALL,
                        )
                    },
                    elapsedRealtimeSource = FakeElapsedRealtime(testScheduler),
                    ringNotifier = notifier,
                ).run(session, SpkiFingerprint(ByteArray(32)), null)
            }.also { runCurrent() }

    private fun ringEnvelope() =
        envelope {
            channel = Channel.CHANNEL_STATUS
            ring = ring { }
        }
}
