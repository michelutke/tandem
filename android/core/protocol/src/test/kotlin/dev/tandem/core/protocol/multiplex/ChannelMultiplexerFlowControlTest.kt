package dev.tandem.core.protocol.multiplex

import app.cash.turbine.test
import dev.tandem.core.protocol.FrameEncoder
import dev.tandem.core.protocol.FrameSink
import dev.tandem.core.protocol.FrameSource
import dev.tandem.core.protocol.flowcontrol.CreditCaps
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.DeviceStatus
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.EnvelopeKt
import dev.tandem.protocol.v1.Heartbeat
import dev.tandem.protocol.v1.creditGrant
import dev.tandem.protocol.v1.envelope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.channels.Channel as KtChannel

/**
 * ChannelMultiplexer flow-control tests (E11-07; SPEC.md #channels-and-flow-control-credits,
 * D-64). Unlike [ChannelMultiplexerTest] (E11-05), these run under `runTest` with Turbine: none of
 * the seams these tests exercise (send-credit suspension, the writer's round-robin, receive-side
 * grant issuance) touch a real blocking pipe, so [FakeFramePipe] below is a small, fully
 * suspend-based byte pipe — safe to drive with a virtual-time scheduler, unlike
 * `InMemoryDuplexPipe` (E00-19), which blocks real threads.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ChannelMultiplexerFlowControlTest {
    @Test
    fun flowControl_zeroCredit_sendSuspendedUntilGrantDelivered() =
        runTest {
            val pipe = FakeFramePipe()
            val a = ChannelMultiplexer(pipe.sourceA, pipe.sinkA)
            backgroundScope.launch { a.start() }

            repeat(CreditCaps.PROTOCOL_MAX) {
                a.send(Channel.CHANNEL_FILES) { deviceStatus = DeviceStatus.getDefaultInstance() }
            }

            val blocked = launch { a.send(Channel.CHANNEL_FILES) { deviceStatus = DeviceStatus.getDefaultInstance() } }
            advanceTimeBy(10.seconds)
            assertTrue(blocked.isActive, "still suspended: FILES credit is exhausted")

            pipe.injectTowardsA(
                rawFrame(Channel.CHANNEL_CONTROL, seq = 1) {
                    this.creditGrant =
                        creditGrant {
                            this.channel = Channel.CHANNEL_FILES
                            this.amount = 1
                        }
                },
            )
            withTimeout(5.seconds) { blocked.join() }

            assertTrue(blocked.isCompleted, "resumed once the grant was delivered")
        }

    @Test
    fun frameWriter_tenFilesQueuedThenNotify_notifyWrittenWithinTwoFrames() =
        runTest {
            val pipe = FakeFramePipe()
            val recordingSink = RecordingSink(pipe.sinkA)
            val a = ChannelMultiplexer(pipe.sourceA, recordingSink)
            backgroundScope.launch { a.start() }

            repeat(10) { a.send(Channel.CHANNEL_FILES) { deviceStatus = DeviceStatus.getDefaultInstance() } }
            a.send(Channel.CHANNEL_NOTIFY) { deviceStatus = DeviceStatus.getDefaultInstance() }

            val firstTwo =
                withTimeout(5.seconds) {
                    List(2) { recordingSink.received.receive() }
                }

            assertTrue(
                firstTwo.any { it.channel == Channel.CHANNEL_NOTIFY },
                "expected NOTIFY within the first 2 frames written, got: ${firstTwo.map { it.channel }}",
            )
        }

    @Test
    fun flowControl_stalledNotifyCollector_filesFramesStillDelivered() =
        runTest {
            val pipe = FakeFramePipe()
            val a = ChannelMultiplexer(pipe.sourceA, pipe.sinkA)
            val b = ChannelMultiplexer(pipe.sourceB, pipe.sinkB)
            backgroundScope.launch { a.start() }
            backgroundScope.launch { b.start() }

            // B never collects NOTIFY's inbound flow below.
            a.send(Channel.CHANNEL_NOTIFY) { deviceStatus = DeviceStatus.getDefaultInstance() }
            a.send(Channel.CHANNEL_FILES) { deviceStatus = DeviceStatus.getDefaultInstance() }

            b.inbound(Channel.CHANNEL_FILES).test {
                assertEquals(Channel.CHANNEL_FILES, awaitItem().channel)
                cancelAndIgnoreRemainingEvents()
            }
        }

    @Test
    fun flowControl_consumedPastTrigger_sendsExactlyOneCreditGrant() =
        runTest {
            val pipe = FakeFramePipe()
            val a = ChannelMultiplexer(pipe.sourceA, pipe.sinkA)
            val recordingSink = RecordingSink(pipe.sinkB)
            val b = ChannelMultiplexer(pipe.sourceB, recordingSink)
            backgroundScope.launch { a.start() }
            backgroundScope.launch { b.start() }

            val trigger = CreditCaps.PROTOCOL_MAX / 2
            repeat(trigger) { a.send(Channel.CHANNEL_FILES) { deviceStatus = DeviceStatus.getDefaultInstance() } }

            b.inbound(Channel.CHANNEL_FILES).test {
                repeat(trigger) { awaitItem() }
                cancelAndIgnoreRemainingEvents()
            }
            advanceUntilIdle()

            val grants = recordingSink.frames.filter { it.payloadCase == Envelope.PayloadCase.CREDIT_GRANT }
            assertEquals(1, grants.size, "expected exactly one CreditGrant, got: $grants")
            assertEquals(Channel.CHANNEL_FILES, grants.single().creditGrant.channel)
        }

    @Test
    fun flowControl_peerSendsBeyondGrant_closesWithCreditViolation() =
        runTest {
            val pipe = FakeFramePipe()
            val b = ChannelMultiplexer(pipe.sourceB, pipe.sinkB)
            backgroundScope.launch { b.start() }

            for (seq in 1..(CreditCaps.PROTOCOL_MAX + 1)) {
                pipe.injectTowardsB(
                    rawFrame(Channel.CHANNEL_FILES, seq.toLong()) {
                        deviceStatus = DeviceStatus.getDefaultInstance()
                    },
                )
            }

            val close = withTimeout(5.seconds) { b.closeReason.await() }
            assertEquals(MultiplexerClose.CreditViolation(Channel.CHANNEL_FILES), close)
        }

    @Test
    fun flowControl_peerGrantAboveCap_closesWithCreditViolation() =
        runTest {
            val pipe = FakeFramePipe()
            val a = ChannelMultiplexer(pipe.sourceA, pipe.sinkA)
            backgroundScope.launch { a.start() }

            pipe.injectTowardsA(
                rawFrame(Channel.CHANNEL_CONTROL, seq = 1) {
                    this.creditGrant =
                        creditGrant {
                            this.channel = Channel.CHANNEL_FILES
                            this.amount = 1
                        }
                },
            )

            val close = withTimeout(5.seconds) { a.closeReason.await() }
            assertEquals(MultiplexerClose.CreditViolation(Channel.CHANNEL_FILES), close)
        }

    @Test
    fun flowControl_controlChannel_neverSuspendsOnCredit() =
        runTest {
            val pipe = FakeFramePipe()
            val a = ChannelMultiplexer(pipe.sourceA, pipe.sinkA)

            withTimeout(5.seconds) {
                repeat(CreditCaps.PROTOCOL_MAX * 4) {
                    a.send(Channel.CHANNEL_CONTROL) { heartbeat = Heartbeat.getDefaultInstance() }
                }
            }
        }

    private companion object {
        fun rawFrame(
            channel: Channel,
            seq: Long,
            ack: Long = 0L,
            payload: EnvelopeKt.Dsl.() -> Unit,
        ): ByteArray =
            FrameEncoder.encodeFrame(
                envelope {
                    payload()
                    this.channel = channel
                    this.seq = seq
                    this.ack = ack
                },
            )
    }

    /** A byte-level in-memory duplex pipe built entirely on suspending [kotlinx.coroutines.channels.Channel]s. */
    private class FakeFramePipe {
        private val toA = KtChannel<Byte>(KtChannel.UNLIMITED)
        private val toB = KtChannel<Byte>(KtChannel.UNLIMITED)

        val sourceA: FrameSource = sourceOver(toA)
        val sinkA: FrameSink = sinkOver(toB)
        val sourceB: FrameSource = sourceOver(toB)
        val sinkB: FrameSink = sinkOver(toA)

        suspend fun injectTowardsA(bytes: ByteArray) = writeAll(toA, bytes)

        suspend fun injectTowardsB(bytes: ByteArray) = writeAll(toB, bytes)

        private suspend fun writeAll(
            channel: KtChannel<Byte>,
            bytes: ByteArray,
        ) {
            for (b in bytes) channel.send(b)
        }

        private fun sourceOver(channel: KtChannel<Byte>): FrameSource =
            FrameSource { buffer, offset, length ->
                if (length == 0) {
                    0
                } else {
                    buffer[offset] = channel.receive()
                    var n = 1
                    while (n < length) {
                        val next = channel.tryReceive()
                        if (next.isFailure) break
                        buffer[offset + n] = next.getOrThrow()
                        n++
                    }
                    n
                }
            }

        private fun sinkOver(channel: KtChannel<Byte>): FrameSink = FrameSink { bytes -> writeAll(channel, bytes) }
    }

    /**
     * Records every frame [FrameEncoder]-written through this sink, forwarding to [delegate] if
     * given. [received] mirrors [frames] as a suspending channel: awaiting from it (rather than
     * writing the frame count and calling `advanceUntilIdle`) is what actually pumps the writer
     * loop's dispatched work forward under `runTest`'s virtual scheduler.
     */
    private class RecordingSink(
        private val delegate: FrameSink? = null,
    ) : FrameSink {
        val frames = mutableListOf<Envelope>()
        val received = KtChannel<Envelope>(KtChannel.UNLIMITED)

        override suspend fun write(bytes: ByteArray) {
            val envelope = Envelope.parseFrom(bytes.copyOfRange(LENGTH_PREFIX_BYTES, bytes.size))
            frames += envelope
            received.trySend(envelope)
            delegate?.write(bytes)
        }

        private companion object {
            const val LENGTH_PREFIX_BYTES = 4
        }
    }
}
