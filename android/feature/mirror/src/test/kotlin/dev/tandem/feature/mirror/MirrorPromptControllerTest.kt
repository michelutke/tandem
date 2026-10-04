package dev.tandem.feature.mirror

import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.mirrorRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.IOException
import java.time.Instant

/** E61-16 `unit:` tests (`docs/planning/backlog/phase-6.yaml`). Plain JUnit5. */
@OptIn(ExperimentalCoroutinesApi::class)
class MirrorPromptControllerTest {
    private class RecordingPresenter : MirrorPromptPresenter {
        var shown = 0
        var visible = false

        override fun show(peerName: String) {
            shown++
            visible = true
        }

        override fun remove() {
            visible = false
        }
    }

    private class RecordingLauncher : ProjectionConsentLauncher {
        var launches = 0

        override fun launchConsent() {
            launches++
        }
    }

    private class Fixture(
        scope: TestScope,
    ) {
        val session = FakeTandemSession().also { it.emitState(ConnectionState.Ready(Instant.EPOCH)) }
        val presenter = RecordingPresenter()
        val launcher = RecordingLauncher()
        var userStarts = 0
        val controller =
            MirrorPromptController(
                session = session,
                presenter = presenter,
                starter = MirrorSessionStarter(launcher),
                peerName = "MacBook Pro",
                scope = scope.backgroundScope,
                onUserStart = { userStarts++ },
            )

        fun request() {
            session.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_CONTROL
                    mirrorRequest = mirrorRequest { }
                },
            )
        }

        fun sentKinds(): List<Envelope.PayloadCase> = session.sentFrames.map { it.payloadCase }
    }

    @Test
    fun mirrorPrompt_mirrorRequestReceived_postsOnePromptAndSendsNothing() =
        runTest(StandardTestDispatcher()) {
            val f = Fixture(this)
            f.controller.start()
            runCurrent()

            f.request()
            runCurrent()

            assertEquals(1, f.presenter.shown)
            assertTrue(f.session.sentFrames.isEmpty())
            assertEquals(0, f.launcher.launches)
            assertEquals(0, f.userStarts)
        }

    @Test
    fun mirrorPrompt_repeatedRequestWhilePending_stillOnePrompt() =
        runTest(StandardTestDispatcher()) {
            val f = Fixture(this)
            f.controller.start()
            runCurrent()

            f.request()
            f.request()
            f.request()
            runCurrent()

            assertEquals(1, f.presenter.shown)
            assertTrue(f.session.sentFrames.isEmpty())
        }

    @Test
    fun mirrorPrompt_noTapWithin30s_sendsMirrorDeclinedAndRemovesPrompt() =
        runTest(StandardTestDispatcher()) {
            val f = Fixture(this)
            f.controller.start()
            runCurrent()
            f.request()
            runCurrent()

            advanceTimeBy(29_999)
            runCurrent()
            assertTrue(f.session.sentFrames.isEmpty())
            advanceTimeBy(1)
            runCurrent()

            assertEquals(listOf(Envelope.PayloadCase.MIRROR_DECLINED), f.sentKinds())
            assertTrue(!f.presenter.visible)
            assertEquals(0, f.launcher.launches)
        }

    @Test
    fun mirrorPrompt_userDeclinesOrDismisses_sendsMirrorDeclined() =
        runTest(StandardTestDispatcher()) {
            val f = Fixture(this)
            f.controller.start()
            runCurrent()
            f.request()
            runCurrent()

            f.controller.onDeclineOrDismiss()
            runCurrent()
            advanceTimeBy(60_000)
            runCurrent()

            assertEquals(listOf(Envelope.PayloadCase.MIRROR_DECLINED), f.sentKinds())
            assertTrue(!f.presenter.visible)
        }

    @Test
    fun mirrorPrompt_consentGranted_sendsRequestMediaTicket() =
        runTest(StandardTestDispatcher()) {
            val f = Fixture(this)
            f.controller.start()
            runCurrent()
            f.request()
            runCurrent()

            f.controller.onStartTapped()
            runCurrent()
            assertEquals(1, f.launcher.launches)
            assertEquals(1, f.userStarts)
            assertTrue(f.session.sentFrames.isEmpty())
            advanceTimeBy(60_000)
            runCurrent()
            assertTrue(f.session.sentFrames.isEmpty())

            f.controller.onConsentResult(granted = true)
            runCurrent()

            assertEquals(listOf(Envelope.PayloadCase.REQUEST_MEDIA_TICKET), f.sentKinds())
            assertTrue(!f.presenter.visible)
        }

    @Test
    fun mirrorPrompt_consentDenied_sendsMirrorDeclined() =
        runTest(StandardTestDispatcher()) {
            val f = Fixture(this)
            f.controller.start()
            runCurrent()
            f.request()
            runCurrent()
            f.controller.onStartTapped()

            f.controller.onConsentResult(granted = false)
            runCurrent()

            assertEquals(listOf(Envelope.PayloadCase.MIRROR_DECLINED), f.sentKinds())
        }

    @Test
    fun mirrorPrompt_startTappedWithoutPendingPrompt_doesNothing() =
        runTest(StandardTestDispatcher()) {
            val f = Fixture(this)
            f.controller.start()
            runCurrent()

            f.controller.onStartTapped()
            runCurrent()

            assertEquals(0, f.launcher.launches)
            assertEquals(0, f.userStarts)
        }

    @Test
    fun mirrorPrompt_requestWhileMirrorActive_sendsMirrorDeclinedAndNoPrompt() =
        runTest(StandardTestDispatcher()) {
            val f = Fixture(this)
            f.controller.start()
            runCurrent()
            f.request()
            runCurrent()
            f.controller.onStartTapped()
            f.controller.onConsentResult(granted = true)
            runCurrent()
            val sentBefore = f.session.sentFrames.size

            f.request()
            runCurrent()

            assertEquals(1, f.presenter.shown)
            assertEquals(Envelope.PayloadCase.MIRROR_DECLINED, f.session.sentFrames[sentBefore].payloadCase)
        }

    @Test
    fun mirrorPrompt_sessionClosesWhilePromptUp_removesPromptAndSendsNothing() =
        runTest(StandardTestDispatcher()) {
            val f = Fixture(this)
            f.controller.start()
            runCurrent()
            f.request()
            runCurrent()

            f.session.emitState(ConnectionState.Disconnected())
            runCurrent()
            f.controller.onStartTapped()
            f.controller.onDeclineOrDismiss()
            advanceTimeBy(60_000)
            runCurrent()

            assertTrue(!f.presenter.visible)
            assertTrue(f.session.sentFrames.isEmpty())
            assertEquals(0, f.launcher.launches)
            assertEquals(0, f.userStarts)
        }

    @Test
    fun mirrorPrompt_timeoutThenTap_onlyDeclined() =
        runTest(StandardTestDispatcher()) {
            val f = Fixture(this)
            f.controller.start()
            runCurrent()
            f.request()
            runCurrent()

            advanceTimeBy(30_001)
            runCurrent()
            f.controller.onStartTapped()
            runCurrent()

            assertEquals(listOf(Envelope.PayloadCase.MIRROR_DECLINED), f.sentKinds())
            assertEquals(0, f.launcher.launches)
            assertEquals(0, f.userStarts)
        }

    @Test
    fun mirrorPrompt_tapAtDeadline_exactlyOneOutcome() =
        runTest(StandardTestDispatcher()) {
            val f = Fixture(this)
            f.controller.start()
            runCurrent()
            f.request()
            runCurrent()

            advanceTimeBy(30_000)
            f.controller.onStartTapped()
            runCurrent()

            assertEquals(f.sentKinds().size + f.launcher.launches, 1)
            assertEquals(f.launcher.launches, f.userStarts)
        }

    @Test
    fun mirrorPrompt_tapThenTimeout_onlyConsentLaunched() =
        runTest(StandardTestDispatcher()) {
            val f = Fixture(this)
            f.controller.start()
            runCurrent()
            f.request()
            runCurrent()

            f.controller.onStartTapped()
            advanceTimeBy(30_000)
            runCurrent()

            assertTrue(f.session.sentFrames.isEmpty())
            assertEquals(1, f.launcher.launches)
        }

    @Test
    fun mirrorPrompt_sendFails_doesNotThrow() =
        runTest(StandardTestDispatcher()) {
            val f = Fixture(this)
            f.controller.start()
            runCurrent()
            f.request()
            runCurrent()

            f.session.failNextSend(IOException("closed"))
            f.controller.onDeclineOrDismiss()
            runCurrent()

            assertTrue(f.session.sentFrames.isEmpty())
            assertTrue(!f.presenter.visible)
        }
}
