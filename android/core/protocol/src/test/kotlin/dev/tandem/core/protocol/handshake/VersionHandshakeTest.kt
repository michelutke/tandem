package dev.tandem.core.protocol.handshake

import dev.tandem.core.protocol.DecodeResult
import dev.tandem.core.protocol.FrameDecoder
import dev.tandem.core.protocol.FrameEncoder
import dev.tandem.core.protocol.FrameSink
import dev.tandem.core.protocol.FrameSource
import dev.tandem.core.protocol.multiplex.ChannelMultiplexer
import dev.tandem.core.testing.TestClock
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.DeviceStatus
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.versionHello
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import kotlinx.coroutines.channels.Channel as KtChannel

/**
 * VersionHandshake tests (E12-15; `docs/planning/backlog/phase-1.yaml` E12-15's `tdd:` list).
 * [FakeWire] is a pure-suspend `FrameSource`/`FrameSink` pair (no real-thread blocking, unlike
 * `InMemoryDuplexPipe`), so the 5 s deadline test can run entirely in `runTest`'s virtual time.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class VersionHandshakeTest {
    @Test
    fun hello_peerSameMajorHigherMinor_stateBecomesReady() =
        runTest {
            val dispatcher = StandardTestDispatcher(testScheduler)
            val wire = FakeWire()
            val multiplexer = ChannelMultiplexer(wire.source, wire.sink)
            backgroundScope.launch(dispatcher) { multiplexer.start() }
            wire.injectFrame(peerHello(major = 1, minor = 5, capabilities = 0))

            val handshake = VersionHandshake(multiplexer, TestClock(testScheduler), dispatcher)
            val outcome = handshake.perform()

            val ready = outcome as HandshakeOutcome.Ready
            assertEquals(5, ready.session.peerMinor)
        }

    @Test
    fun hello_peerDifferentMajor_closesVersionMismatchAndFailedState() =
        runTest {
            val dispatcher = StandardTestDispatcher(testScheduler)
            val wire = FakeWire()
            val multiplexer = ChannelMultiplexer(wire.source, wire.sink)
            backgroundScope.launch(dispatcher) { multiplexer.start() }
            wire.injectFrame(peerHello(major = 2, minor = 0, capabilities = 0))

            val handshake = VersionHandshake(multiplexer, TestClock(testScheduler), dispatcher)
            val outcome = handshake.perform()

            assertEquals(HandshakeOutcome.Failed(HandshakeFailure.VersionMismatch(2, 0)), outcome)
        }

    @Test
    fun hello_notifySendBeforePeerHello_zeroNotifyBytesOnWire() =
        runTest {
            val dispatcher = StandardTestDispatcher(testScheduler)
            val wire = FakeWire()
            val multiplexer = ChannelMultiplexer(wire.source, wire.sink)
            backgroundScope.launch(dispatcher) { multiplexer.start() }

            val handshake = VersionHandshake(multiplexer, TestClock(testScheduler), dispatcher)
            backgroundScope.launch(dispatcher) {
                handshake.awaitReady()
                multiplexer.send(Channel.CHANNEL_NOTIFY) { deviceStatus = DeviceStatus.getDefaultInstance() }
            }
            backgroundScope.launch(dispatcher) { handshake.perform() }

            runCurrent()
            assertTrue(
                wire.sentFrames.none { it.channel == Channel.CHANNEL_NOTIFY },
                "no NOTIFY bytes before peer hello",
            )

            wire.injectFrame(peerHello(major = 1, minor = 0, capabilities = 0))
            runCurrent()

            assertTrue(wire.sentFrames.any { it.channel == Channel.CHANNEL_NOTIFY }, "NOTIFY sent once Ready")
        }

    @Test
    fun hello_peerUnknownCapabilityBit_ignoredAndOthersExposed() =
        runTest {
            val dispatcher = StandardTestDispatcher(testScheduler)
            val wire = FakeWire()
            val multiplexer = ChannelMultiplexer(wire.source, wire.sink)
            backgroundScope.launch(dispatcher) { multiplexer.start() }
            val unknownBits = 0b101L
            wire.injectFrame(peerHello(major = 1, minor = 0, capabilities = unknownBits))

            val handshake = VersionHandshake(multiplexer, TestClock(testScheduler), dispatcher)
            val outcome = handshake.perform()

            val ready = outcome as HandshakeOutcome.Ready
            assertEquals(unknownBits, ready.session.capabilities)
        }

    @Test
    fun hello_noPeerHelloWithin5s_closesProtocolTimeout() =
        runTest {
            val dispatcher = StandardTestDispatcher(testScheduler)
            val wire = FakeWire()
            val multiplexer = ChannelMultiplexer(wire.source, wire.sink)
            backgroundScope.launch(dispatcher) { multiplexer.start() }

            val handshake = VersionHandshake(multiplexer, TestClock(testScheduler), dispatcher)
            val outcome = handshake.perform()

            assertEquals(HandshakeOutcome.Failed(HandshakeFailure.Timeout), outcome)
        }

    private companion object {
        fun peerHello(
            major: Int,
            minor: Int,
            capabilities: Long,
        ): Envelope =
            envelope {
                this.channel = Channel.CHANNEL_CONTROL
                this.seq = 1
                this.ack = 0
                this.versionHello =
                    versionHello {
                        this.major = major
                        this.minor = minor
                        this.capabilities = capabilities
                    }
            }
    }

    /**
     * A pure-suspend `FrameSource`/`FrameSink` pair: [source] suspends on a `Channel<Byte>` rather
     * than blocking a real thread, so it cooperates with `runTest`'s virtual-time scheduler (unlike
     * `InMemoryDuplexPipe`, which is deliberately real-thread-blocking, E00-19). [sentFrames]
     * decodes each frame [ChannelMultiplexer]'s writer loop hands to [sink] (one full encoded frame
     * per call, E11-07) back into an [Envelope] for assertions.
     */
    private class FakeWire {
        private val inboundBytes = KtChannel<Byte>(KtChannel.UNLIMITED)
        val sentFrames = mutableListOf<Envelope>()

        val source =
            FrameSource { buffer, offset, length ->
                buffer[offset] = inboundBytes.receive()
                var count = 1
                while (count < length) {
                    val next = inboundBytes.tryReceive().getOrNull() ?: break
                    buffer[offset + count] = next
                    count++
                }
                count
            }

        val sink =
            FrameSink { bytes ->
                var offset = 0
                val frameSource =
                    FrameSource { buffer, bufOffset, length ->
                        val remaining = bytes.size - offset
                        if (remaining <= 0) return@FrameSource -1
                        val toCopy = minOf(length, remaining)
                        bytes.copyInto(buffer, bufOffset, offset, offset + toCopy)
                        offset += toCopy
                        toCopy
                    }
                when (val result = FrameDecoder.decodeFrame(frameSource)) {
                    is DecodeResult.Frame -> sentFrames.add(result.envelope)
                    else -> error("FakeWire could not decode its own encoded frame: $result")
                }
            }

        suspend fun injectFrame(envelope: Envelope) {
            for (byte in FrameEncoder.encodeFrame(envelope)) {
                inboundBytes.send(byte)
            }
        }
    }
}
