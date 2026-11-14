package dev.tandem.core.transport

import dev.tandem.core.protocol.CloseCode
import dev.tandem.core.protocol.FrameSink
import dev.tandem.core.protocol.FrameSource
import dev.tandem.core.protocol.connection.ConnectionEvent
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.protocol.connection.ConnectionStateMachine
import dev.tandem.core.protocol.handshake.HandshakeFailure
import dev.tandem.core.protocol.handshake.HandshakeOutcome
import dev.tandem.core.protocol.handshake.VersionHandshake
import dev.tandem.core.protocol.multiplex.ChannelMultiplexer
import dev.tandem.core.protocol.multiplex.MultiplexerClose
import dev.tandem.core.protocol.multiplex.MultiplexerClosedException
import dev.tandem.core.transport.heartbeat.ControlFrameRateCap
import dev.tandem.core.transport.heartbeat.DeadPeerDetector
import dev.tandem.core.transport.heartbeat.DeviceIdleSource
import dev.tandem.core.transport.heartbeat.HeartbeatResponder
import dev.tandem.core.transport.heartbeat.UnsolicitedHeartbeatTimer
import dev.tandem.core.transport.time.ElapsedRealtimeSource
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.EnvelopeKt
import dev.tandem.protocol.v1.heartbeat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.runInterruptible
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.IOException
import java.time.Clock
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.time.Duration.Companion.seconds

/**
 * E20-15 liveness dependencies for [ByteStreamSession]: supplying this starts a [HeartbeatResponder],
 * [UnsolicitedHeartbeatTimer] and [DeadPeerDetector] once this session reaches
 * [ConnectionState.Ready]. Omitted by every caller not yet ready to supply a real
 * [DeviceIdleSource] (e.g. `harness/jvm-client`, a plain JVM process with no Android runtime to back
 * one) -- those sessions behave exactly as before this issue, with no liveness enforcement of their
 * own (the JVM harness plays the Mac side of a connection, which never needed one; E20-05 is that
 * side's own contract).
 */
class HeartbeatDependencies(
    val elapsedRealtimeSource: ElapsedRealtimeSource,
    val deviceIdleSource: DeviceIdleSource,
)

/**
 * [TandemSession] over a real [ByteStream] (E12-11; aligned with the macOS twin, E12-12). By the
 * time a [ByteStream] instance exists, its TCP connect and TLS handshake have already completed —
 * that remains owned by whichever transport constructs it (e.g. the SSLSocket session, E12-04);
 * this class only adapts [byteStream]'s blocking [ByteStream.input]/[ByteStream.output] into a
 * [ChannelMultiplexer]'s [FrameSource]/[FrameSink] seam, drives [ConnectionStateMachine] (E12-08)
 * through the E12-15 [VersionHandshake] atop it, and gates every feature-channel [send] on
 * [VersionHandshake.awaitReady] (SPEC.md: "No application frame... MAY be sent... before both
 * hellos have been exchanged").
 *
 * [dispatcher] plays the same dual role it plays for [ConnectionStateMachine] and
 * [VersionHandshake]: it is where their `delay`-based deadlines run, and — since neither
 * `core/protocol` nor this class picks its own dispatcher — it is also where this class's
 * [ChannelMultiplexer.start] reader/writer loop and blocking [ByteStream] reads/writes
 * (via `runInterruptible`) run, mirroring `ChannelMultiplexerTest`'s own `sourceFor`/`sinkFor`.
 */
@Suppress("TooManyFunctions") // one session lifecycle: handshake, heartbeat, close and send steps share state
class ByteStreamSession(
    private val byteStream: ByteStream,
    clock: Clock,
    private val dispatcher: CoroutineDispatcher,
    private val heartbeatDependencies: HeartbeatDependencies? = null,
    private val markers: ReconnectMarkers = ReconnectMarkers.None,
) : TandemSession {
    private val frameSource =
        FrameSource { buffer, offset, length -> runInterruptible { byteStream.input.read(buffer, offset, length) } }
    private val frameSink =
        FrameSink { bytes -> runInterruptible { byteStream.output.write(bytes) } }

    /**
     * `internal` rather than `private` only so tests can assert this session leaves no leaked
     * child coroutine behind once closed (E20-15 verifier finding #3's regression test).
     */
    internal val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val connection = ConnectionStateMachine(clock, dispatcher)
    private val multiplexer = ChannelMultiplexer(frameSource, frameSink)
    private val handshake = VersionHandshake(multiplexer, clock, dispatcher)

    /**
     * The hello exchange, started in `init` once [multiplexer] is running. The close watcher joins
     * it before closing, so a peer close racing the exchange can neither cancel it mid-flight nor
     * let a late hello complete a session that is already closed.
     */
    private val handshakeJob = scope.launch(start = CoroutineStart.LAZY) { performHandshake() }

    /**
     * Sole collector of [multiplexer]'s inbound flows; each channel's source waits for
     * [VersionHandshake.awaitReady] first so the handshake's own CONTROL read is never raced.
     */
    private val inboundDispatcher =
        ChannelDispatcher(scope, replayLast = { it.hasRotationChallenge() }) { channel ->
            flow {
                if (awaitReadyOrClosed()) emitAll(multiplexer.inbound(channel).map { it.payload })
            }
        }

    /**
     * `true` once the handshake is Ready; `false` if [multiplexer] closes and the hello exchange ends
     * without Ready, e.g. the peer hangs up before its hello so [VersionHandshake.perform] throws.
     * A burst of hello, frames and EOF still reports Ready, because the close is only acted on once
     * the exchange has finished.
     */
    private suspend fun awaitReadyOrClosed(): Boolean =
        coroutineScope {
            val ready = async(start = CoroutineStart.UNDISPATCHED) { handshake.awaitReady() }
            val closedAfterHandshake =
                async {
                    multiplexer.closeReason.await()
                    handshakeJob.join()
                    state.value is ConnectionState.Ready
                }
            val isReady =
                select {
                    ready.onAwait { true }
                    closedAfterHandshake.onAwait { it }
                }
            ready.cancel()
            closedAfterHandshake.cancel()
            isReady
        }

    private var heartbeatResponder: HeartbeatResponder? = null
    private var unsolicitedHeartbeatTimer: UnsolicitedHeartbeatTimer? = null
    private var deadPeerDetector: DeadPeerDetector? = null
    private var controlFrameRateCap: ControlFrameRateCap? = null

    /**
     * Guards [performClose] so it runs at most once, whether triggered by [close] or by
     * [multiplexer]'s own [ChannelMultiplexer.closeReason] completing (E20-15 verifier #1/#2).
     */
    private val closed = AtomicBoolean(false)

    /**
     * The [startHeartbeatLifecycle] coroutine's own [Job], cancelled by [performClose] so a
     * session that never reaches [ConnectionState.Ready] cannot leak it (E20-15 verifier #3).
     */
    private var heartbeatLifecycleJob: Job? = null

    override val state: StateFlow<ConnectionState> = connection.state

    init {
        connection.handle(ConnectionEvent.Connect)
        connection.handle(ConnectionEvent.SocketOpened)
        connection.handle(ConnectionEvent.HandshakeCompleted)
        controlFrameRateCap = heartbeatDependencies?.let(::startControlFrameRateCap)
        scope.launch { multiplexer.start() }
        handshakeJob.start()
        scope.launch {
            multiplexer.closeReason.await()
            handshakeJob.join()
            withTimeoutOrNull(PEER_CLOSE_DRAIN) { inboundDispatcher.awaitLaneCompleted(Channel.CHANNEL_CONTROL) }
            performClose("connection closed")
        }
        if (heartbeatDependencies != null) {
            heartbeatLifecycleJob = scope.launch { startHeartbeatLifecycle(heartbeatDependencies) }
        }
    }

    /**
     * Starts the E20-15 liveness classes once this session reaches [ConnectionState.Ready] --
     * mirroring the macOS twin's own `HeartbeatController`, constructed once its connection reaches
     * the same state (E20-05's `ListenerFactory`) -- and stops them the moment [multiplexer] itself
     * closes, for any reason, mirroring that same twin's `ListenerFactory` calling
     * `HeartbeatController.stop()` "once this connection's own ChannelMultiplexer closes, for any
     * reason" (E20-15 verifier finding #1: without this, a peer EOF/IOException/seq violation closes
     * [multiplexer] but nothing stops the heartbeat trio, so its next send throws
     * [MultiplexerClosedException] uncaught).
     *
     * If [close] races ahead of [ConnectionState.Ready] -- either before this resumes, or while the
     * three heartbeat objects below are being constructed -- [closed] is already `true` and this
     * either returns without constructing them or immediately stops the ones it just built (E20-15
     * verifier finding #2): a [close] that races this coroutine can never leave an orphaned trio
     * running against an already-dead session.
     *
     * The close watcher that tears this session down when [multiplexer] closes is started in
     * `init`, independent of [heartbeatDependencies], so a peer close always reaches
     * [ConnectionState.Disconnected].
     */
    private suspend fun startHeartbeatLifecycle(dependencies: HeartbeatDependencies) {
        state.first { it is ConnectionState.Ready }
        if (closed.get()) return

        @Suppress("TooGenericExceptionCaught", "SwallowedException")
        val sendHeartbeat: suspend () -> Unit = {
            try {
                send(Channel.CHANNEL_CONTROL) { heartbeat = heartbeat {} }
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (e: Exception) {
                // The connection closed between this being scheduled and this running --
                // [MultiplexerClosedException] if [multiplexer] had already completed
                // [ChannelMultiplexer.closeReason] by the time [send] checked, or the raw
                // [java.io.IOException] a write already in flight sees if [byteStream] itself gets
                // torn down mid-write (mirrors the macOS twin's own `try?` around this same send,
                // E20-15 verifier finding #1). Either way, nothing is left to send a heartbeat to --
                // never let this crash the app.
            }
        }

        heartbeatResponder =
            HeartbeatResponder(
                received = multiplexer.received,
                sendHeartbeat = sendHeartbeat,
                elapsedRealtimeSource = dependencies.elapsedRealtimeSource,
                dispatcher = dispatcher,
            ).apply { start() }

        unsolicitedHeartbeatTimer =
            UnsolicitedHeartbeatTimer(
                sent = multiplexer.sent,
                isIdle = dependencies.deviceIdleSource.isIdle,
                sendHeartbeat = sendHeartbeat,
                dispatcher = dispatcher,
            ).apply { start() }

        deadPeerDetector =
            DeadPeerDetector(
                received = multiplexer.received.map { },
                deviceIdleSource = dependencies.deviceIdleSource,
                elapsedRealtimeSource = dependencies.elapsedRealtimeSource,
                onDead = {
                    markers.dead()
                    close()
                },
                dispatcher = dispatcher,
            ).apply { start() }

        if (closed.get()) {
            heartbeatResponder?.close()
            unsolicitedHeartbeatTimer?.close()
            deadPeerDetector?.close()
            return
        }
    }

    /** Subscribes before [multiplexer] starts reading, so no frame of a flood predates the counter. */
    private fun startControlFrameRateCap(dependencies: HeartbeatDependencies): ControlFrameRateCap =
        ControlFrameRateCap(
            received = multiplexer.received,
            elapsedRealtimeSource = dependencies.elapsedRealtimeSource,
            onExceeded = ::closeControlFrameCapExceeded,
            dispatcher = dispatcher,
        ).apply { start() }

    /** D-61: a `CONTROL` flood fails the session visibly with `LIMIT_EXCEEDED` (no wire signal on the phone). */
    private fun closeControlFrameCapExceeded() {
        performClose("control frame cap exceeded")
        connection.handle(ConnectionEvent.HandshakeError(CloseCode.LIMIT_EXCEEDED.name))
    }

    /**
     * [VersionHandshake.perform] can throw rather than return a [HandshakeOutcome.Failed] --
     * e.g. its own [ChannelMultiplexer.send] of this side's hello racing a peer-triggered
     * [ChannelMultiplexer] close (a rejected peer's connection reset arriving before this side's
     * hello is sent) throws [dev.tandem.core.protocol.multiplex.MultiplexerClosedException].
     * Uncaught, that would crash this coroutine silently and leave [connection] stuck in
     * [ConnectionState.HelloExchange] forever (E12-13: reproduced against the real Mac listener
     * rejecting an unseeded client's certificate) -- every exception here is instead reported the
     * same way a [HandshakeOutcome.Failed] already is, per [ConnectionEvent.HandshakeError]'s own
     * "legal from any state" contract.
     */
    @Suppress("TooGenericExceptionCaught") // any failure must reach HandshakeError, see above
    private suspend fun performHandshake() {
        try {
            when (val outcome = handshake.perform()) {
                is HandshakeOutcome.Ready -> {
                    // Marked before Ready is published, so an observer of Ready that closes at once
                    // can never record `disconnected` ahead of `ready` (reconnect bookkeeping order).
                    markers.ready()
                    connection.handle(ConnectionEvent.CompatibleHelloReceived)
                }

                is HandshakeOutcome.Failed -> {
                    connection.handle(handshakeFailureEvent(outcome.reason))
                }
            }
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (e: Exception) {
            connection.handle(failureEventFor(e))
        }
    }

    /**
     * A failed hello exchange is [ConnectionEvent.PeerRejectedCertificate] only when the connection
     * ended with a TLS alert rejecting this phone's client certificate; a reset, EOF or timeout is an
     * ordinary [ConnectionEvent.HandshakeError].
     */
    private suspend fun failureEventFor(cause: Exception): ConnectionEvent {
        val close =
            (cause as? MultiplexerClosedException)?.close
                ?: withTimeoutOrNull(CLOSE_REASON_WAIT) { multiplexer.closeReason.await() }
        return if (close is MultiplexerClose.SourceFailed && ClientCertificateAlerts.isRejection(close.cause)) {
            ConnectionEvent.PeerRejectedCertificate
        } else {
            ConnectionEvent.HandshakeError(cause.message ?: cause.toString())
        }
    }

    private fun handshakeFailureEvent(reason: HandshakeFailure): ConnectionEvent =
        when (reason) {
            is HandshakeFailure.VersionMismatch -> ConnectionEvent.VersionMismatch
            HandshakeFailure.Timeout -> ConnectionEvent.HelloTimeout
            HandshakeFailure.UnexpectedFirstPayload -> ConnectionEvent.HandshakeError(CloseCode.MALFORMED_FRAME.name)
        }

    override suspend fun send(
        channel: Channel,
        payload: EnvelopeKt.Dsl.() -> Unit,
    ) {
        if (channel != Channel.CHANNEL_CONTROL) handshake.awaitReady()
        multiplexer.send(channel, payload)
    }

    override suspend fun sendFinal(
        channel: Channel,
        payload: EnvelopeKt.Dsl.() -> Unit,
    ) {
        try {
            if (channel != Channel.CHANNEL_CONTROL) handshake.awaitReady()
            multiplexer.sendAndAwaitWritten(channel, payload)
        } finally {
            performClose("closed locally", graceful = true)
        }
    }

    override fun receive(channel: Channel): Flow<Envelope> = inboundDispatcher.subscribe(channel)

    override fun close() = performClose("closed locally")

    /**
     * The actual close logic, idempotent via [closed]: runs at most once whether reached through a
     * caller's [close] or through the watcher started in `init` observing
     * [ChannelMultiplexer.closeReason] complete on its own (a peer EOF, an IOException, or a seq/ack
     * violation -- E20-15 verifier finding #1). [heartbeatLifecycleJob] is cancelled here too, so a
     * session that never reaches [ConnectionState.Ready] before this runs cannot leak that coroutine
     * (E20-15 verifier finding #3).
     */
    private fun performClose(
        reason: String,
        graceful: Boolean = false,
    ) {
        if (!closed.compareAndSet(false, true)) return
        heartbeatLifecycleJob?.cancel()
        heartbeatResponder?.close()
        unsolicitedHeartbeatTimer?.close()
        deadPeerDetector?.close()
        controlFrameRateCap?.close()
        try {
            closeStream(graceful)
        } finally {
            if (state.value is ConnectionState.Ready) markers.disconnected()
            connection.handle(ConnectionEvent.SocketClosed(reason))
            connection.close()
            scope.launch(start = CoroutineStart.UNDISPATCHED) { withContext(NonCancellable) { multiplexer.close() } }
            scope.cancel()
        }
    }

    @Suppress("SwallowedException") // a failing close leaves nothing to release; the teardown goes on
    private fun closeStream(graceful: Boolean) {
        try {
            if (graceful) byteStream.closeGracefully() else byteStream.closeAbruptly()
        } catch (_: IOException) {
            return
        }
    }

    private companion object {
        /** How long a peer-closed session lets already-received CONTROL frames (`PairRejected`) reach subscribers. */
        val PEER_CLOSE_DRAIN = 2.seconds

        /** How long a failed hello exchange waits for the multiplexer to publish why the connection ended. */
        val CLOSE_REASON_WAIT = 1.seconds
    }
}
