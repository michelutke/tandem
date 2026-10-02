package dev.tandem.core.protocol.multiplex

import app.cash.turbine.test
import dev.tandem.core.protocol.CloseCode
import dev.tandem.core.protocol.DecodeResult
import dev.tandem.core.protocol.FrameDecoder
import dev.tandem.core.protocol.FrameEncoder
import dev.tandem.core.protocol.FrameSink
import dev.tandem.core.protocol.FrameSource
import dev.tandem.core.protocol.MalformedFrameReason
import dev.tandem.core.protocol.flowcontrol.CreditCaps
import dev.tandem.core.testing.InMemoryDuplexPipe
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.DeviceStatus
import dev.tandem.protocol.v1.envelope
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.runInterruptible
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.time.Duration.Companion.seconds

/**
 * ChannelMultiplexer tests (E11-05). Two multiplexers are wired over `InMemoryDuplexPipe`
 * (E00-19) as `docs/planning/backlog/phase-1.yaml` E11-05's acceptance criteria describe,
 * collected with Turbine (E00-04). `runBlocking` with real threads is used rather than `runTest` +
 * `StandardTestDispatcher`: `InMemoryDuplexPipe` blocks real threads internally (`ReentrantLock`/
 * `Condition`) via `runInterruptible`, exactly as `InMemoryDuplexPipeTest` itself does — mixing
 * that with a virtual-time scheduler risks the reader-loop coroutine never being resumed.
 */
class ChannelMultiplexerTest {
    @Test
    fun multiplexer_frameOnNotify_notEmittedOnAnyOtherChannelFlow() =
        muxTest {
            val pipe = InMemoryDuplexPipe()
            val a = ChannelMultiplexer(sourceFor(pipe.endpointA), sinkFor(pipe.endpointA))
            val b = ChannelMultiplexer(sourceFor(pipe.endpointB), sinkFor(pipe.endpointB))
            // E11-07: `send` only enqueues; `a`'s own writer loop (launched by `a.start()`) is
            // what actually puts bytes on the wire for `b` to read.
            launch { a.start() }
            launch { b.start() }

            b.inbound(Channel.CHANNEL_NOTIFY).test {
                a.send(Channel.CHANNEL_NOTIFY) { deviceStatus = DeviceStatus.getDefaultInstance() }
                assertEquals(Channel.CHANNEL_NOTIFY, awaitItem().channel)
                cancelAndIgnoreRemainingEvents()
            }

            for (channel in OTHER_CHANNELS) {
                b.inbound(channel).test {
                    expectNoEvents()
                    cancelAndIgnoreRemainingEvents()
                }
            }
        }

    @Test
    fun multiplexer_sendsOnTwoChannels_seqCountsIndependentlyFromOne() =
        muxTest {
            val pipe = InMemoryDuplexPipe()
            val a = ChannelMultiplexer(sourceFor(pipe.endpointA), sinkFor(pipe.endpointA))
            val b = ChannelMultiplexer(sourceFor(pipe.endpointB), sinkFor(pipe.endpointB))
            launch { a.start() }
            launch { b.start() }

            repeat(3) { a.send(Channel.CHANNEL_NOTIFY) { deviceStatus = DeviceStatus.getDefaultInstance() } }
            a.send(Channel.CHANNEL_FILES) { deviceStatus = DeviceStatus.getDefaultInstance() }

            b.inbound(Channel.CHANNEL_NOTIFY).test {
                assertEquals(1L, awaitItem().seq)
                assertEquals(2L, awaitItem().seq)
                assertEquals(3L, awaitItem().seq)
                cancelAndIgnoreRemainingEvents()
            }
            b.inbound(Channel.CHANNEL_FILES).test {
                assertEquals(1L, awaitItem().seq)
                cancelAndIgnoreRemainingEvents()
            }
        }

    @Test
    fun multiplexer_receivedSeq1And3_ackIs1UntilSeq2Arrives() =
        muxTest {
            // Only B runs a multiplexer: frames are injected raw towards B, and B's outgoing acks
            // are read back one frame at a time from a raw FrameSource over the B→A direction (not
            // from a snapshot of captured bytes, since E11-07's writer loop delivers a `send`
            // asynchronously: a snapshot taken immediately after `send` returns could race it).
            val pipe = InMemoryDuplexPipe()
            val b = ChannelMultiplexer(sourceFor(pipe.endpointB), sinkFor(pipe.endpointB))
            launch { b.start() }
            val bOutgoing = sourceFor(pipe.endpointA)

            injectAndAwaitRouted(pipe, b, Channel.CHANNEL_NOTIFY, seq = 1)
            b.send(Channel.CHANNEL_NOTIFY) { deviceStatus = DeviceStatus.getDefaultInstance() }
            assertEquals(1L, nextAckSentByB(bOutgoing), "ack after seq 1 arrives")

            injectAndAwaitRouted(pipe, b, Channel.CHANNEL_NOTIFY, seq = 3)
            b.send(Channel.CHANNEL_NOTIFY) { deviceStatus = DeviceStatus.getDefaultInstance() }
            assertEquals(1L, nextAckSentByB(bOutgoing), "ack unchanged: seq 3 is a held gap")

            injectAndAwaitRouted(pipe, b, Channel.CHANNEL_NOTIFY, seq = 2)
            b.send(Channel.CHANNEL_NOTIFY) { deviceStatus = DeviceStatus.getDefaultInstance() }
            assertEquals(3L, nextAckSentByB(bOutgoing), "ack folds in seq 3 once seq 2 fills the gap")
        }

    @Test
    fun multiplexer_regressingIncomingSeq_appliesSpecDefinedOutcome() =
        muxTest {
            val pipe = InMemoryDuplexPipe()
            val b = ChannelMultiplexer(sourceFor(pipe.endpointB), sinkFor(pipe.endpointB))
            val readerJob = launch { b.start() }

            injectAndAwaitRouted(pipe, b, Channel.CHANNEL_NOTIFY, seq = 1)
            // A duplicate of the already-received seq 1 is at the watermark (D-57): fatal.
            pipe.injectTowardsB(rawFrame(Channel.CHANNEL_NOTIFY, seq = 1))

            val close = withTimeout(5.seconds) { b.closeReason.await() }

            assertEquals(
                MultiplexerClose.Violation(CloseCode.MALFORMED_FRAME, MalformedFrameReason.SEQ_REGRESSION),
                close,
            )
            b.inbound(Channel.CHANNEL_NOTIFY).test { awaitComplete() }
            readerJob.join()
        }

    @Test
    fun multiplexer_seqGapExceedsProtocolMax_closesWithSeqGapTooLarge() =
        muxTest {
            val pipe = InMemoryDuplexPipe()
            val b = ChannelMultiplexer(sourceFor(pipe.endpointB), sinkFor(pipe.endpointB))
            val readerJob = launch { b.start() }

            // Never sends seq 1, so every one of these stays pending above the watermark (a
            // legitimate gap-fill per D-57) until the pending set holds exactly PROTOCOL_MAX
            // entries (seq 2..PROTOCOL_MAX+1).
            for (seq in 2..(CreditCaps.PROTOCOL_MAX + 1)) {
                injectAndAwaitRouted(pipe, b, Channel.CHANNEL_NOTIFY, seq = seq.toLong())
            }
            // One more above-watermark seq would push the pending set past PROTOCOL_MAX: no
            // legitimate, credit-bound peer can reach this (D-64), so it is fatal.
            pipe.injectTowardsB(rawFrame(Channel.CHANNEL_NOTIFY, seq = (CreditCaps.PROTOCOL_MAX + 2).toLong()))

            val close = withTimeout(5.seconds) { b.closeReason.await() }

            assertEquals(
                MultiplexerClose.Violation(CloseCode.MALFORMED_FRAME, MalformedFrameReason.SEQ_GAP_TOO_LARGE),
                close,
            )
            b.inbound(Channel.CHANNEL_NOTIFY).test { awaitComplete() }
            readerJob.join()
        }

    @Test
    fun channelMultiplexer_closeAbruptlyDuringInFlightWrite_noUncaughtExceptionAndCloseReasonCompletes() =
        muxTest {
            val writeStarted = CompletableDeferred<Unit>()
            val abruptClose = CompletableDeferred<Unit>()
            val uncaught = CopyOnWriteArrayList<Throwable>()
            val source = FrameSource { _, _, _ -> awaitCancellation() }
            val sink =
                FrameSink {
                    writeStarted.complete(Unit)
                    abruptClose.await()
                    throw IOException("closed abruptly")
                }
            val mux = ChannelMultiplexer(source, sink)
            val handler = CoroutineExceptionHandler { _, e -> uncaught += e }
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO + handler)
            val startJob = scope.launch { mux.start() }

            mux.send(Channel.CHANNEL_NOTIFY) { deviceStatus = DeviceStatus.getDefaultInstance() }
            writeStarted.await()
            abruptClose.complete(Unit)

            val close = withTimeout(5.seconds) { mux.closeReason.await() }
            assertTrue(close is MultiplexerClose.SourceFailed, "close reason: $close")
            startJob.cancelAndJoin()
            assertEquals(emptyList<Throwable>(), uncaught)
        }

    private companion object {
        /**
         * Runs on real IO threads (the pipe blocks threads) and cancels the reader loops when the
         * body finishes; otherwise `runBlocking` would wait forever for `start()`, which only returns
         * at end of stream.
         */
        fun muxTest(block: suspend CoroutineScope.() -> Unit) {
            runBlocking(Dispatchers.IO) {
                try {
                    block()
                } finally {
                    coroutineContext.cancelChildren()
                }
            }
        }

        val OTHER_CHANNELS =
            listOf(
                Channel.CHANNEL_CONTROL,
                Channel.CHANNEL_CLIPBOARD,
                Channel.CHANNEL_FILES,
                Channel.CHANNEL_SMS,
                Channel.CHANNEL_CONTACTS,
                Channel.CHANNEL_CALLS,
                Channel.CHANNEL_INPUT,
                Channel.CHANNEL_STATUS,
            )

        fun sourceFor(endpoint: InMemoryDuplexPipe.Endpoint): FrameSource =
            FrameSource { buffer, offset, length -> runInterruptible { endpoint.input.read(buffer, offset, length) } }

        fun sinkFor(endpoint: InMemoryDuplexPipe.Endpoint): FrameSink = FrameSink { bytes -> endpoint.write(bytes) }

        fun rawFrame(
            channel: Channel,
            seq: Long,
            ack: Long = 0L,
        ): ByteArray =
            FrameEncoder.encodeFrame(
                envelope {
                    this.channel = channel
                    this.seq = seq
                    this.ack = ack
                    this.deviceStatus = DeviceStatus.getDefaultInstance()
                },
            )

        /** Suspends until the next frame [source] delivers, returning its `ack`. */
        suspend fun nextAckSentByB(source: FrameSource): Long =
            when (val result = FrameDecoder.decodeFrame(source)) {
                is DecodeResult.Frame -> result.envelope.ack
                else -> error("B sent no frame: $result")
            }

        /**
         * Injects a raw frame directly onto the wire toward [b] (bypassing [ChannelMultiplexer.send],
         * which never lets a caller pick a `seq` itself) and waits until [b]'s reader loop has routed
         * it — proving that frame's seq/ack bookkeeping has already been applied — before the caller
         * does anything that depends on that bookkeeping (E11-05 acceptance: seq 1 then 3 then 2).
         */
        suspend fun injectAndAwaitRouted(
            pipe: InMemoryDuplexPipe,
            b: ChannelMultiplexer,
            channel: Channel,
            seq: Long,
        ) {
            pipe.injectTowardsB(rawFrame(channel, seq))
            b.inbound(channel).first()
        }
    }
}
