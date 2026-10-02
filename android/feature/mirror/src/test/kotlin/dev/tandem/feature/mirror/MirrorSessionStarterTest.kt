package dev.tandem.feature.mirror

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** MirrorSessionStarter E61-02 tests (`docs/planning/backlog/phase-6.yaml` E61-02's `tdd:` list). Plain JUnit5. */
class MirrorSessionStarterTest {
    private class RecordingConsentLauncher : ProjectionConsentLauncher {
        var launchCount = 0

        override fun launchConsent() {
            launchCount++
        }
    }

    @Test
    fun mirrorSessionStarter_secondStart_launchesConsentIntentAgain() {
        val launcher = RecordingConsentLauncher()
        val starter = MirrorSessionStarter(launcher)

        starter.onLocalStartAction()
        starter.onConsentResult(granted = true)
        starter.onLocalStartAction()

        assertEquals(2, launcher.launchCount)
    }

    @Test
    fun mirrorSessionStarter_noLocalStartAction_neverLaunchesConsent() {
        val launcher = RecordingConsentLauncher()
        val starter = MirrorSessionStarter(launcher)

        starter.onConsentResult(granted = true)
        starter.onConsentResult(granted = false)

        assertEquals(0, launcher.launchCount)
        assertEquals(MirrorSessionState.NotStarted, starter.state)
    }

    @Test
    fun mirrorSessionStarter_consentDenied_returnsToNotStarted() {
        val starter = MirrorSessionStarter(RecordingConsentLauncher())

        starter.onLocalStartAction()
        assertEquals(MirrorSessionState.AwaitingConsent, starter.state)
        starter.onConsentResult(granted = false)

        assertEquals(MirrorSessionState.NotStarted, starter.state)
    }

    @Test
    fun mirrorSessionStarter_consentGranted_movesToConsentGranted() {
        val starter = MirrorSessionStarter(RecordingConsentLauncher())

        starter.onLocalStartAction()
        starter.onConsentResult(granted = true)

        assertEquals(MirrorSessionState.ConsentGranted, starter.state)
    }

    @Test
    fun mirrorSessionStarter_startWhileAwaitingConsent_launchesOnlyOnce() {
        val launcher = RecordingConsentLauncher()
        val starter = MirrorSessionStarter(launcher)

        starter.onLocalStartAction()
        starter.onLocalStartAction()

        assertEquals(1, launcher.launchCount)
    }
}
