package dev.tandem.app.mirror

import android.view.Surface
import com.google.protobuf.ByteString
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.ByteStream
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.core.transport.media.MediaStreamFactory
import dev.tandem.core.transport.reconnect.CandidateAddress
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.feature.input.AccessibilityActions
import dev.tandem.feature.input.DropLog
import dev.tandem.feature.input.FocusedInput
import dev.tandem.feature.input.GateDropReason
import dev.tandem.feature.input.GestureStroke
import dev.tandem.feature.input.GestureTranslator
import dev.tandem.feature.input.InputActionHandler
import dev.tandem.feature.input.NotificationPresenter
import dev.tandem.feature.input.OverlayBadge
import dev.tandem.feature.input.RemoteInputIndicator
import dev.tandem.feature.input.RemoteInputTarget
import dev.tandem.feature.input.Size
import dev.tandem.feature.mirror.CaptureSource
import dev.tandem.feature.mirror.DisplayChangeSource
import dev.tandem.feature.mirror.EncodedBuffer
import dev.tandem.feature.mirror.EncoderFactory
import dev.tandem.feature.mirror.MirrorPromptActionDispatcher
import dev.tandem.feature.mirror.MirrorPromptPresenter
import dev.tandem.feature.mirror.NoDisplayChanges
import dev.tandem.feature.mirror.ProjectionConsentLauncher
import dev.tandem.feature.mirror.VideoEncoder
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.GlobalActionKind
import dev.tandem.protocol.v1.MediaHello
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.globalAction
import dev.tandem.protocol.v1.inputEvent
import dev.tandem.protocol.v1.mediaTicketGrant
import dev.tandem.protocol.v1.mirrorRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.time.Clock
import java.time.Instant
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.SSLHandshakeException

/**
 * E62-11 unit tests (`docs/planning/backlog/phase-6.yaml` E62-11's `tdd:` list) plus the invariant 8
 * check that no input executes without the user's consent. Plain JUnit5 with real I/O threads.
 */
class MirrorFeatureTest {
    private val peer = SpkiFingerprint(ByteArray(32) { 9 })
    private val sessionIdBytes = ByteArray(16) { 7 }

    private class FakePresenter : MirrorPromptPresenter {
        val shown = AtomicInteger()

        override fun show(peerName: String) {
            shown.incrementAndGet()
        }

        override fun remove() = Unit
    }

    private class FakeCapture : CaptureSource {
        val stops = AtomicInteger()

        override fun start(surface: Surface) = Unit

        override fun stop() {
            stops.incrementAndGet()
        }
    }

    private class BlockingEncoder : VideoEncoder {
        val closes = AtomicInteger()
        private val closed = CountDownLatch(1)

        override fun requestSyncFrame() = Unit

        override fun setBitrate(bitsPerSecond: Int) = Unit

        override fun nextOutput(): EncodedBuffer? {
            closed.await()
            return null
        }

        override fun close() {
            closes.incrementAndGet()
            closed.countDown()
        }
    }

    private class RecordingStream : ByteStream {
        val closes = AtomicInteger()
        private val release = CountDownLatch(1)
        override val input: InputStream =
            object : InputStream() {
                override fun read(): Int {
                    release.await()
                    return -1
                }
            }
        val written = ByteArrayOutputStream()
        override val output: OutputStream = written

        override fun closeGracefully() {
            closes.incrementAndGet()
            release.countDown()
        }

        override fun closeAbruptly() {
            closes.incrementAndGet()
            release.countDown()
        }
    }

    private class FakePlatform : MirrorPlatform {
        val launches = AtomicInteger()
        val captureStops = AtomicInteger()
        val captureServiceStarts = AtomicInteger()
        val failures = CopyOnWriteArrayList<MirrorFailure>()
        val capture = FakeCapture()
        val encoder = BlockingEncoder()

        @Volatile
        var listener: ((Boolean) -> Unit)? = null

        override val consentLauncher = ProjectionConsentLauncher { launches.incrementAndGet() }

        override fun setConsentListener(listener: ((granted: Boolean) -> Unit)?) {
            this.listener = listener
        }

        override fun displaySize() = Size(1080, 2400)

        override fun encoderFactory() = EncoderFactory { _, _ -> encoder }

        override fun displayChanges(): DisplayChangeSource = NoDisplayChanges

        override suspend fun startCaptureService(): Boolean {
            captureServiceStarts.incrementAndGet()
            return true
        }

        override fun stopCaptureService() {
            captureStops.incrementAndGet()
        }

        override fun openCapture(
            width: Int,
            height: Int,
        ): CaptureSource = capture

        override fun showFailure(failure: MirrorFailure) {
            failures += failure
        }
    }

    private class RecordingActions : AccessibilityActions {
        val globalActions = CopyOnWriteArrayList<Int>()
        val strokes = CopyOnWriteArrayList<GestureStroke>()

        override fun performGlobalAction(action: Int): Boolean {
            globalActions += action
            return true
        }

        override fun findFocusedInput(): FocusedInput? = null

        override fun dispatchGesture(stroke: GestureStroke): Boolean {
            strokes += stroke
            return true
        }
    }

    private class FakeNotification : NotificationPresenter {
        var posted = false

        override fun post(): Boolean {
            posted = true
            return true
        }

        override fun remove() {
            posted = false
        }

        override fun isPosted() = posted
    }

    private class FakeOverlay : OverlayBadge {
        var attached = false

        override fun attach(): Boolean {
            attached = true
            return true
        }

        override fun detach() {
            attached = false
        }

        override fun isAttached() = attached
    }

    private inner class Fixture(
        pinMismatch: Boolean = false,
        unreachable: Boolean = false,
    ) {
        val session = FakeTandemSession().apply { emitState(ConnectionState.Ready(Instant.EPOCH)) }
        val platform = FakePlatform()
        val presenter = FakePresenter()
        val stream = RecordingStream()
        val streamFactory =
            MediaStreamFactory { _, _ ->
                if (pinMismatch) throw SSLHandshakeException("pin").apply { initCause(CertificateException("pin")) }
                if (unreachable) throw IOException("down")
                stream
            }
        val actions = RecordingActions()
        val notification = FakeNotification()
        val overlay = FakeOverlay()
        val targetLookups = AtomicInteger()
        val drops = CopyOnWriteArrayList<GateDropReason>()
        val target =
            RemoteInputTarget(
                handler = InputActionHandler(actions),
                translator = GestureTranslator(actions),
                indicator = RemoteInputIndicator(notification, overlay),
            )
        val feature =
            MirrorFeature(
                platform = platform,
                presenter = presenter,
                peerName = { "Mac" },
                controlAddress = { CandidateAddress("127.0.0.1", 1) },
                mediaStreams = streamFactory,
                elapsedRealtime = ElapsedRealtimeSource { 0L },
                inputTarget = {
                    targetLookups.incrementAndGet()
                    target
                },
                dropLog =
                    object : DropLog {
                        override fun dropped(
                            reason: GateDropReason,
                            eventType: String,
                        ) {
                            drops += reason
                        }

                        override fun rateLimited(count: Int) = Unit
                    },
                clock = Clock.systemUTC(),
                ioDispatcher = Dispatchers.IO,
                random =
                    object : SecureRandom() {
                        override fun nextBytes(bytes: ByteArray) {
                            sessionIdBytes.copyInto(bytes)
                        }
                    },
            )

        fun mirrorRequest(): Envelope =
            envelope {
                channel = Channel.CHANNEL_CONTROL
                mirrorRequest = mirrorRequest { }
            }

        fun homeAction(id: ByteArray = sessionIdBytes): Envelope =
            envelope {
                channel = Channel.CHANNEL_INPUT
                inputEvent =
                    inputEvent {
                        sessionId = ByteString.copyFrom(id)
                        globalAction = globalAction { action = GlobalActionKind.GLOBAL_ACTION_KIND_HOME }
                    }
            }

        suspend fun tapStart() {
            await { MirrorPromptActionDispatcher.controller != null }
            session.emitIncoming(mirrorRequest())
            await { presenter.shown.get() == 1 }
            MirrorPromptActionDispatcher.controller!!.onStartTapped()
            await { platform.launches.get() == 1 && platform.listener != null }
        }

        fun mediaHello(): MediaHello {
            val bytes = stream.written.toByteArray()
            val length = ByteBuffer.wrap(bytes).int
            return MediaHello.parseFrom(bytes.copyOfRange(4, 4 + length))
        }

        suspend fun startMirror(expectIndicator: Boolean = true) {
            tapStart()
            platform.listener!!(true)
            await { session.sentFrames.any { it.hasRequestMediaTicket() } }
            session.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_CONTROL
                    mediaTicketGrant = mediaTicketGrant { ticket = ByteString.copyFrom(ByteArray(32) { 1 }) }
                },
            )
            if (expectIndicator) await { notification.posted && overlay.attached }
        }
    }

    @AfterEach
    fun resetDispatcher() {
        MirrorPromptActionDispatcher.controller = null
    }

    @Test
    fun appMirrorComposition_sessionReady_promptControllerAndGateAttachedOnce() =
        runBlocking {
            val f = Fixture()
            val job = launchFeature(f)

            await { MirrorPromptActionDispatcher.controller != null }
            f.session.emitIncoming(f.mirrorRequest())
            f.session.emitIncoming(f.mirrorRequest())
            await { f.presenter.shown.get() == 1 }

            assertEquals(1, f.targetLookups.get())
            assertEquals(1, f.presenter.shown.get())
            assertEquals(0, f.platform.launches.get())
            assertTrue(f.session.sentFrames.isEmpty())
            job.cancelAndJoin()
        }

    @Test
    fun appMirrorComposition_sessionEnded_mediaEncoderIndicatorAndGateTornDown() =
        runBlocking {
            val f = Fixture()
            val job = launchFeature(f)
            f.startMirror()
            await { f.session.sentFrames.count { it.hasRequestMediaTicket() } == 1 }
            f.session.emitIncoming(f.homeAction())
            await { f.actions.globalActions.size == 1 }

            f.session.close()
            job.join()

            assertEquals(
                1,
                f.platform.encoder.closes
                    .get(),
            )
            assertTrue(
                f.platform.capture.stops
                    .get() >= 1,
            )
            assertTrue(f.stream.closes.get() >= 1)
            assertTrue(!f.notification.posted && !f.overlay.attached)
            assertTrue(f.platform.captureStops.get() >= 1)
            assertNull(MirrorPromptActionDispatcher.controller)
            assertEquals(1, f.actions.globalActions.size)
        }

    @Test
    fun appMirrorComposition_inputWithoutUserConsent_executesNothing() =
        runBlocking {
            val f = Fixture()
            val job = launchFeature(f)
            await { MirrorPromptActionDispatcher.controller != null }

            f.session.emitIncoming(f.homeAction())
            await { f.drops.isNotEmpty() }

            assertTrue(f.actions.globalActions.isEmpty())
            assertTrue(f.actions.strokes.isEmpty())
            assertEquals(listOf(GateDropReason.NoConsent), f.drops)
            job.cancelAndJoin()
        }

    @Test
    fun appMirrorComposition_inputWithForeignSessionId_executesNothing() =
        runBlocking {
            val f = Fixture()
            val job = launchFeature(f)
            f.startMirror()

            f.session.emitIncoming(f.homeAction(ByteArray(16) { 1 }))
            await { f.drops.isNotEmpty() }

            assertTrue(f.actions.globalActions.isEmpty())
            job.cancelAndJoin()
        }

    @Test
    fun appMirrorComposition_mediaDialPinMismatch_showsFailClosedErrorAndStartsNoCapture() =
        runBlocking {
            val f = Fixture(pinMismatch = true)
            val job = launchFeature(f)

            f.startMirror(expectIndicator = false)
            await { f.platform.failures.isNotEmpty() && f.session.sentFrames.any { it.hasMirrorDeclined() } }

            assertEquals(listOf(MirrorFailure.PinMismatch), f.platform.failures)
            assertEquals(
                0,
                f.platform.encoder.closes
                    .get(),
            )
            assertTrue(!f.notification.posted && !f.overlay.attached)
            assertTrue(f.session.sentFrames.any { it.hasMirrorDeclined() })
            job.cancelAndJoin()
        }

    @Test
    fun appMirrorComposition_sessionDropsDuringTicketWait_captureServiceStoppedAndConsentRevoked() =
        runBlocking {
            val f = Fixture()
            val job = launchFeature(f)
            f.tapStart()
            f.platform.listener!!(true)
            await { f.session.sentFrames.any { it.hasRequestMediaTicket() } }

            job.cancelAndJoin()

            assertEquals(1, f.platform.captureStops.get())
            assertEquals(
                1,
                f.platform.capture.stops
                    .get(),
            )
            f.session.emitIncoming(f.homeAction())
            assertTrue(f.actions.globalActions.isEmpty())
        }

    @Test
    fun appMirrorComposition_consentDenied_revokesGrantAndStartsNothing() =
        runBlocking {
            val f = Fixture()
            val job = launchFeature(f)
            f.tapStart()

            f.platform.listener!!(false)
            await { f.session.sentFrames.any { it.hasMirrorDeclined() } }
            f.session.emitIncoming(f.homeAction())
            await { f.drops.isNotEmpty() }

            assertEquals(listOf(GateDropReason.NoConsent), f.drops)
            assertEquals(0, f.platform.captureServiceStarts.get())
            assertTrue(f.actions.globalActions.isEmpty())
            job.cancelAndJoin()
        }

    @Test
    fun appMirrorComposition_staleConsentResultWithoutUserStart_startsNothing() =
        runBlocking {
            val f = Fixture()
            val job = launchFeature(f)
            await { MirrorPromptActionDispatcher.controller != null && f.platform.listener != null }

            f.platform.listener!!(true)
            kotlinx.coroutines.delay(SETTLE_MILLIS)

            assertEquals(0, f.platform.captureServiceStarts.get())
            assertTrue(f.session.sentFrames.none { it.hasRequestMediaTicket() })
            job.cancelAndJoin()
        }

    @Test
    fun appMirrorComposition_inputAfterMirrorEnded_dropped() =
        runBlocking {
            val f = Fixture()
            val job = launchFeature(f)
            f.startMirror()
            f.session.emitIncoming(f.homeAction())
            await { f.actions.globalActions.size == 1 }

            f.stream.closeAbruptly()
            await { !f.notification.posted && !f.overlay.attached }
            await {
                f.session.emitIncoming(f.homeAction())
                f.drops.isNotEmpty()
            }

            assertEquals(1, f.actions.globalActions.size)
            assertTrue(f.drops.all { it == GateDropReason.NoConsent })
            job.cancelAndJoin()
        }

    @Test
    fun appMirrorComposition_mediaHello_carriesSessionIdInputGateAccepts() =
        runBlocking {
            val f = Fixture()
            val job = launchFeature(f)
            f.startMirror()

            val hello = f.mediaHello()
            f.session.emitIncoming(f.homeAction(hello.mirrorSessionId.toByteArray()))
            await { f.actions.globalActions.size == 1 }

            assertEquals(ByteString.copyFrom(sessionIdBytes), hello.mirrorSessionId)
            assertEquals(ByteString.copyFrom(ByteArray(32) { 1 }), hello.ticket)
            job.cancelAndJoin()
        }

    @Test
    fun appMirrorComposition_mediaDialUnreachable_showsVisibleFailure() =
        runBlocking {
            val f = Fixture(unreachable = true)
            val job = launchFeature(f)

            f.startMirror(expectIndicator = false)
            await { f.platform.failures.isNotEmpty() }

            assertEquals(listOf(MirrorFailure.Unreachable), f.platform.failures)
            job.cancelAndJoin()
        }

    private fun CoroutineScope.launchFeature(f: Fixture): Job =
        launch(Dispatchers.Default) {
            f.feature.run(f.session, peer, null)
        }

    private suspend fun await(condition: () -> Boolean) =
        withTimeout(TIMEOUT_MILLIS) {
            while (!condition()) kotlinx.coroutines.delay(POLL_MILLIS)
        }

    private companion object {
        const val TIMEOUT_MILLIS = 10_000L
        const val POLL_MILLIS = 10L
        const val SETTLE_MILLIS = 300L
    }
}
