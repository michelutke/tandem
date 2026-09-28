package dev.tandem.app.ring

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// E23-05 tdd:
//   unit: ringHandler_ringReceived_alarmStreamMaxAndPlaybackStarted
//   unit: ringHandler_ringStopped_restoresPreviousAlarmVolume
//   unit: ringHandler_totalSilenceFilter_switchesToAlarmsAndRestoresOnStop
//   unit: ringHandler_policyAccessMissing_showsExplanationBeforeSettings
class RingHandlerTest {
    @Test
    fun ringHandler_ringReceived_alarmStreamMaxAndPlaybackStarted() {
        val alarmPlayer = FakeAlarmPlayer()
        val ringHandler =
            RingHandler(
                alarmPlayer = alarmPlayer,
                notificationPolicyAccess =
                    FakeNotificationPolicyAccess(access = true, initialFilter = InterruptionFilter.ALL),
            )

        ringHandler.ring()

        assertEquals(FakeAlarmPlayer.MAX_VOLUME, alarmPlayer.alarmVolume)
        assertTrue(alarmPlayer.isPlaying)
    }

    @Test
    fun ringHandler_ringStopped_restoresPreviousAlarmVolume() {
        val alarmPlayer = FakeAlarmPlayer(initialVolume = 5)
        val ringHandler =
            RingHandler(
                alarmPlayer = alarmPlayer,
                notificationPolicyAccess =
                    FakeNotificationPolicyAccess(access = true, initialFilter = InterruptionFilter.ALL),
            )

        ringHandler.ring()
        ringHandler.stop()

        assertEquals(5, alarmPlayer.alarmVolume)
        assertFalse(alarmPlayer.isPlaying)
    }

    @Test
    fun ringHandler_totalSilenceFilter_switchesToAlarmsAndRestoresOnStop() {
        val notificationPolicyAccess =
            FakeNotificationPolicyAccess(access = true, initialFilter = InterruptionFilter.NONE)
        val ringHandler =
            RingHandler(
                alarmPlayer = FakeAlarmPlayer(),
                notificationPolicyAccess = notificationPolicyAccess,
            )

        ringHandler.ring()
        assertEquals(InterruptionFilter.ALARMS, notificationPolicyAccess.filter)

        ringHandler.stop()
        assertEquals(InterruptionFilter.NONE, notificationPolicyAccess.filter)
    }

    @Test
    fun ringHandler_policyAccessMissing_showsExplanationBeforeSettings() {
        val notificationPolicyAccess =
            FakeNotificationPolicyAccess(access = false, initialFilter = InterruptionFilter.NONE)
        val ringHandler =
            RingHandler(
                alarmPlayer = FakeAlarmPlayer(),
                notificationPolicyAccess = notificationPolicyAccess,
            )

        assertFalse(ringHandler.needsPolicyExplanation)
        ringHandler.ring()

        assertTrue(ringHandler.needsPolicyExplanation)
        // Without access, the filter is never touched -- opening settings is a user action driven
        // by RingPolicyExplanationScreen, not something ring() does itself.
        assertEquals(InterruptionFilter.NONE, notificationPolicyAccess.filter)
    }

    @Test
    fun ringHandler_policyAccessPresent_doesNotNeedExplanation() {
        val ringHandler =
            RingHandler(
                alarmPlayer = FakeAlarmPlayer(),
                notificationPolicyAccess =
                    FakeNotificationPolicyAccess(access = true, initialFilter = InterruptionFilter.ALL),
            )

        ringHandler.ring()

        assertFalse(ringHandler.needsPolicyExplanation)
    }
}
