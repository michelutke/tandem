package dev.tandem.core.transport

import dev.tandem.core.protocol.FrameSink
import dev.tandem.core.protocol.FrameSource
import dev.tandem.core.protocol.connection.ConnectionEvent
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.protocol.connection.ConnectionStateMachine
import dev.tandem.core.protocol.handshake.HandshakeOutcome
import dev.tandem.core.protocol.handshake.VersionHandshake
import dev.tandem.core.protocol.multiplex.ChannelMultiplexer
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.EnvelopeKt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.runInterruptible
import java.time.Clock

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
class ByteStreamSession(
    private val byteStream: ByteStream,
    clock: Clock,
    dispatcher: CoroutineDispatcher,
) : TandemSession {
    private val frameSource =
        FrameSource { buffer, offset, length -> runInterruptible { byteStream.input.read(buffer, offset, length) } }
    private val frameSink =
        FrameSink { bytes -> runInterruptible { byteStream.output.write(bytes) } }

    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val connection = ConnectionStateMachine(clock, dispatcher)
    private val multiplexer = ChannelMultiplexer(frameSource, frameSink)
    private val handshake = VersionHandshake(multiplexer, clock, dispatcher)

    override val state: StateFlow<ConnectionState> = connection.state

    init {
        connection.handle(ConnectionEvent.Connect)
        connection.handle(ConnectionEvent.SocketOpened)
        connection.handle(ConnectionEvent.HandshakeCompleted)
        scope.launch { multiplexer.start() }
        scope.launch { performHandshake() }
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
                    connection.handle(ConnectionEvent.CompatibleHelloReceived)
                }

                is HandshakeOutcome.Failed -> {
                    connection.handle(ConnectionEvent.HandshakeError(outcome.reason.toString()))
                }
            }
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (e: Exception) {
            connection.handle(ConnectionEvent.HandshakeError(e.message ?: e.toString()))
        }
    }

    override suspend fun send(
        channel: Channel,
        payload: EnvelopeKt.Dsl.() -> Unit,
    ) {
        if (channel != Channel.CHANNEL_CONTROL) handshake.awaitReady()
        multiplexer.send(channel, payload)
    }

    override fun receive(channel: Channel): Flow<Envelope> = multiplexer.inbound(channel).map { it.payload }

    override fun close() {
        byteStream.closeAbruptly()
        connection.handle(ConnectionEvent.SocketClosed("closed locally"))
        connection.close()
    }
}
