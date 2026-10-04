package dev.tandem.app.mirror

import com.google.protobuf.ByteString
import dev.tandem.app.connection.SessionFeature
import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.protocol.multiplex.MultiplexerClosedException
import dev.tandem.core.transport.ByteStream
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.media.MediaConnectionLifecycle
import dev.tandem.core.transport.media.MediaDialResult
import dev.tandem.core.transport.media.MediaDialer
import dev.tandem.core.transport.media.MediaStreamFactory
import dev.tandem.core.transport.reconnect.CandidateAddress
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.feature.input.DropLog
import dev.tandem.feature.input.IndicatorGateState
import dev.tandem.feature.input.InputGate
import dev.tandem.feature.input.MirrorConsent
import dev.tandem.feature.input.RemoteInputTarget
import dev.tandem.feature.input.Size
import dev.tandem.feature.mirror.CaptureSource
import dev.tandem.feature.mirror.EncodePipeline
import dev.tandem.feature.mirror.EncoderConfigBuilder
import dev.tandem.feature.mirror.MirrorIndicator
import dev.tandem.feature.mirror.MirrorPromptActionDispatcher
import dev.tandem.feature.mirror.MirrorPromptController
import dev.tandem.feature.mirror.MirrorPromptPresenter
import dev.tandem.feature.mirror.MirrorSessionLifecycle
import dev.tandem.feature.mirror.MirrorSessionStarter
import dev.tandem.feature.mirror.RotationPlanner
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.mirrorDeclined
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
import java.security.SecureRandom
import java.time.Clock

/**
 * Composes the mirror and remote-input stack onto every Ready session (E62-11, F-9.1, F-9.3). One
 * [MirrorRound] is attached at a time; it ends when its mirror ends (or the session does), and the
 * next round re-arms the prompt for a later `MirrorRequest`.
 */
@Suppress("LongParameterList") // composition seams: platform, media transport, input target, clock, dispatcher
class MirrorFeature(
    private val platform: MirrorPlatform,
    private val presenter: MirrorPromptPresenter,
    private val peerName: suspend (SpkiFingerprint) -> String,
    private val controlAddress: (TandemSession) -> CandidateAddress?,
    private val mediaStreams: MediaStreamFactory,
    private val elapsedRealtime: ElapsedRealtimeSource,
    private val inputTarget: () -> RemoteInputTarget?,
    private val dropLog: DropLog,
    private val clock: Clock,
    private val ioDispatcher: CoroutineDispatcher,
    private val random: SecureRandom,
    private val sdkInt: Int,
) : SessionFeature {
    override suspend fun run(
        session: TandemSession,
        peer: SpkiFingerprint,
        peerSpkiDer: ByteArray?,
    ) {
        while (session.state.value is ConnectionState.Ready) {
            MirrorRound(session, peer).run()
        }
    }

    private fun mediaDialer(
        session: TandemSession,
        peer: SpkiFingerprint,
    ) = MediaDialer(
        session = session,
        streamFactory = mediaStreams,
        pinSource = PinSource { listOf(peer) },
        elapsedRealtime = elapsedRealtime,
        ioDispatcher = ioDispatcher,
    )

    private fun inputGate(
        target: RemoteInputTarget,
        consent: MirrorConsent,
        peer: SpkiFingerprint,
        media: MediaConnectionLifecycle,
    ) = InputGate(
        consent = consent,
        live = IndicatorGateState(target.indicator, { media.mirrorActive.value }, { peer.base64Url }),
        handler = target.handler,
        translator = target.translator,
        dropLog = dropLog,
        clock = clock,
    )

    private inner class MirrorRound(
        private val session: TandemSession,
        private val peer: SpkiFingerprint,
    ) {
        private val consent = MirrorConsent()
        private val ended = CompletableDeferred<Unit>()
        private val target = inputTarget()
        private val sessionId = ByteString.copyFrom(ByteArray(SESSION_ID_BYTES).also(random::nextBytes))
        private val starter = MirrorSessionStarter(platform.consentLauncher)

        @Volatile
        private var gate: InputGate? = null

        @Volatile
        private var capture: CaptureSource? = null

        @Volatile
        private var lifecycle: MirrorSessionLifecycle? = null

        suspend fun run() =
            coroutineScope {
                val media = MediaConnectionLifecycle(session, mediaDialer(session, peer), this)
                gate = target?.let { inputGate(it, consent, peer, media) }
                val controller = promptController(this)
                MirrorPromptActionDispatcher.controller = controller
                platform.setConsentListener { granted ->
                    controller.onConsentResult(granted)
                    if (granted) launch { startMirror(this, media) }
                }
                controller.start()
                launch { routeInput() }
                try {
                    ended.await()
                } finally {
                    withContext(NonCancellable) { teardown(controller, media) }
                    coroutineContext.job.cancelChildren()
                }
            }

        private suspend fun promptController(scope: CoroutineScope) =
            MirrorPromptController(
                session = TicketlessSession(session),
                presenter = presenter,
                starter = starter,
                peerName = peerName(peer),
                scope = scope,
                onUserStart = { consent.grantFromUserAction(sessionId, peer.base64Url) },
            )

        private suspend fun routeInput() {
            val router = RemoteInputRouter(::gate, ::streamSize, platform::displaySize)
            session.receive(Channel.CHANNEL_INPUT).collect { router.route(it) }
        }

        private fun streamSize(): Size {
            val display = platform.displaySize()
            val planned = RotationPlanner.plan(display.width, display.height)
            return Size(planned.width, planned.height)
        }

        private suspend fun startMirror(
            scope: CoroutineScope,
            media: MediaConnectionLifecycle,
        ) {
            val address = controlAddress(session)
            val size = streamSize()
            val opened =
                if (address != null &&
                    platform.startCaptureService()
                ) {
                    platform.openCapture(size.width, size.height)
                } else {
                    null
                }
            if (address == null || opened == null) return abort(MirrorFailure.Unreachable)
            capture = opened
            when (val dialed = media.start(address)) {
                is MediaDialResult.Connected -> runMirror(scope, opened, dialed.stream, size)
                MediaDialResult.PinMismatch -> abort(MirrorFailure.PinMismatch)
                else -> abort(MirrorFailure.Unreachable)
            }
        }

        private fun runMirror(
            scope: CoroutineScope,
            capture: CaptureSource,
            stream: ByteStream,
            size: Size,
        ) {
            val pipeline =
                EncodePipeline(
                    encoderFactory = platform.encoderFactory(),
                    capture = capture,
                    config = EncoderConfigBuilder.build(sdkInt, size.width, size.height),
                    stream = stream,
                    ioDispatcher = ioDispatcher,
                    displayChanges = platform.displayChanges(),
                )
            val mirror = MirrorSessionLifecycle(pipeline, session, StoppedIndicator(), scope)
            lifecycle = mirror
            target?.indicator?.show()
            mirror.start()
            scope.launch(ioDispatcher) {
                MediaControlReader(stream.input, pipeline::onKeyframeRequest).run()
                mirror.stop()
            }
        }

        private inner class StoppedIndicator : MirrorIndicator {
            override fun onMirrorStopped() {
                consent.revoke()
                target?.indicator?.hide()
                platform.stopCaptureService()
                ended.complete(Unit)
            }
        }

        private suspend fun abort(failure: MirrorFailure) {
            capture?.stop()
            consent.revoke()
            platform.stopCaptureService()
            if (failure == MirrorFailure.PinMismatch) platform.showFailure(failure)
            declineQuietly()
            ended.complete(Unit)
        }

        private suspend fun declineQuietly() {
            try {
                session.send(Channel.CHANNEL_CONTROL) { mirrorDeclined = mirrorDeclined { } }
            } catch (_: MultiplexerClosedException) {
                return
            } catch (_: IOException) {
                return
            }
        }

        private suspend fun teardown(
            controller: MirrorPromptController,
            media: MediaConnectionLifecycle,
        ) {
            platform.setConsentListener(null)
            if (MirrorPromptActionDispatcher.controller === controller) MirrorPromptActionDispatcher.controller = null
            controller.stop()
            lifecycle?.stop() ?: capture?.stop()
            consent.revoke()
            gate = null
            target?.indicator?.hide()
            media.stop()
        }
    }

    private companion object {
        const val SESSION_ID_BYTES = 16
    }
}
