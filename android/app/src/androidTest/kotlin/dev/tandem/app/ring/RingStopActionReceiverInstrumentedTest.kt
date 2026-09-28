package dev.tandem.app.ring

import android.app.Application
import android.app.NotificationManager
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.core.transport.time.SystemElapsedRealtimeSource
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

// E23-06 tdd:
//   instrumented: ringNotification_stopActionTapped_alarmInactiveWithin1s
//
// Runs on a real device/emulator (Gradle Managed Devices, E00-21), not Robolectric: whether the
// STREAM_ALARM playback configuration actually goes away is real AudioManager/MediaPlayer
// behaviour Robolectric's shadows don't model faithfully. RingStopActionReceiver.onReceive is
// called directly on a receiver whose ringControllerProvider seam has been set to a
// FakeTandemSession-backed RingController -- the same seam-substitution BootReceiverTest already
// uses for serviceStarterFactory -- rather than a real system broadcast dispatch, because no
// production composition root wires a live RingController anywhere yet (RingStopActionReceiver's
// own kdoc; same gap RevokeHandler/UnpairAction are in, E14-26/E20-21). What this test exercises
// for real is the acceptance criterion itself: tapping "Stop" makes the alarm stream inactive
// within 1 s.
@RunWith(AndroidJUnit4::class)
class RingStopActionReceiverInstrumentedTest {
    private val context = ApplicationProvider.getApplicationContext<Application>()
    private val audioManager = context.getSystemService(AudioManager::class.java)

    @After
    fun tearDown() {
        RingNotification.cancel(context)
        context.getSystemService(NotificationManager::class.java).cancelAll()
    }

    @Test
    fun ringNotification_stopActionTapped_alarmInactiveWithin1s() {
        val ringController =
            RingController(
                ringHandler = RingHandler(SystemAlarmPlayer(context), SystemNotificationPolicyAccess(context)),
                session = FakeTandemSession(),
                elapsedRealtimeSource = SystemElapsedRealtimeSource,
            )
        val receiver = RingStopActionReceiver()
        receiver.ringControllerProvider = { ringController }

        ringController.ring()
        RingNotification.show(context)
        // Setup wait, not the timed acceptance criterion below -- a shared CI runner's audio HAL
        // can be slow to register a fresh AudioTrack's playback configuration under load (observed
        // for real: a ToneGenerator fallback -- no alarm sound file installed on that managed-
        // device image -- took longer than 1s to first appear in activePlaybackConfigurations, with
        // no assertion failure once given headroom). Give this setup wait CI-only headroom; the
        // Stop-response bound below is the actual "...Within1s" acceptance criterion and stays 1s.
        assertTrue(
            "alarm stream should be active once ringing",
            waitUntil(RING_START_TIMEOUT_MILLIS) { isAlarmStreamActive() },
        )

        receiver.onReceive(context, Intent(RingStopActionReceiver.ACTION_STOP))

        assertTrue(
            "alarm stream should be inactive within 1s of the Stop action",
            waitUntil(TIMEOUT_MILLIS) { !isAlarmStreamActive() },
        )
    }

    private fun isAlarmStreamActive(): Boolean =
        audioManager.activePlaybackConfigurations.any { it.audioAttributes.usage == AudioAttributes.USAGE_ALARM }

    private fun waitUntil(
        timeoutMillis: Long,
        condition: () -> Boolean,
    ): Boolean {
        val deadline = System.nanoTime() + timeoutMillis * NANOS_PER_MILLI
        while (System.nanoTime() < deadline) {
            if (condition()) return true
            Thread.sleep(POLL_INTERVAL_MILLIS)
        }
        return condition()
    }

    private companion object {
        const val TIMEOUT_MILLIS = 1_000L
        const val RING_START_TIMEOUT_MILLIS = 5_000L
        const val POLL_INTERVAL_MILLIS = 50L
        const val NANOS_PER_MILLI = 1_000_000L
    }
}
