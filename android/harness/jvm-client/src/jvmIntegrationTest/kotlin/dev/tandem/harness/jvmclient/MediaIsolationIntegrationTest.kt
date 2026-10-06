package dev.tandem.harness.jvmclient

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.PinningTrustManager
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.ByteStream
import dev.tandem.core.transport.ByteStreamSession
import dev.tandem.core.transport.tls.SslClientFactory
import dev.tandem.core.transport.tls.SslSocketByteStream
import dev.tandem.feature.files.FileSender
import dev.tandem.feature.files.FilesScheduler
import dev.tandem.feature.files.SendRequest
import dev.tandem.feature.files.SenderState
import dev.tandem.feature.files.SourceFileReader
import dev.tandem.harness.jvmclient.latency.NearestRankPercentile
import dev.tandem.harness.jvmclient.testserver.AcceptAnyTrustManager
import dev.tandem.harness.jvmclient.testserver.TestIdentity
import dev.tandem.harness.jvmclient.testserver.TestServerKeyManager
import dev.tandem.harness.jvmclient.testserver.TestTlsServer
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.MediaMessage
import dev.tandem.protocol.v1.TransferReason
import dev.tandem.protocol.v1.fileAccept
import dev.tandem.protocol.v1.fileCancel
import dev.tandem.protocol.v1.mediaFrame
import dev.tandem.protocol.v1.mediaMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.DataInputStream
import java.io.InputStream
import java.net.InetAddress
import java.nio.ByteBuffer
import java.time.Clock
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource

/**
 * E60-07 tdd: integration: mediaIsolation_controlSaturatedByFileTransfer_p95DelayWithin10msOfBaseline.
 *
 * Two real Conscrypt mTLS loopback connections to an in-process peer standing in for the Mac server
 * (ADR-005's control + media pair, no app launch). A synthetic 30 fps `MediaFrame` stream runs on the
 * media connection first alone (baseline), then while the real [FileSender] (E40-03) saturates the
 * control connection's FILES channel through the real `ChannelMultiplexer` credit ledgers
 * (E11-07/E11-08). Delivery delay is arrival minus send on one monotonic clock.
 */
class MediaIsolationIntegrationTest {
    @Test
    fun mediaIsolation_controlSaturatedByFileTransfer_p95DelayWithin10msOfBaseline() {
        val result = runScenario()

        assertEquals(FRAME_COUNT, result.baselineMicros.size)
        assertEquals(FRAME_COUNT, result.saturatedMicros.size)
        val baselineP95 = NearestRankPercentile.p95(result.baselineMicros)
        val saturatedP95 = NearestRankPercentile.p95(result.saturatedMicros)
        assertTrue(result.senderState is SenderState.Sending, "FILES transfer left Sending before the saturated media window ended: ${result.senderState}")
        assertTrue(
            saturatedP95 <= baselineP95 + WITHIN_BASELINE_MICROS,
            "media p95 saturated $saturatedP95 us vs baseline $baselineP95 us",
        )
        assertTrue(saturatedP95 < P95_BUDGET_MICROS, "media p95 saturated was $saturatedP95 us")
    }

    private fun runScenario(): ScenarioResult {
        HarnessConscryptProvider.ensureInstalled()
        val serverIdentity = TestIdentity("server")
        val clientIdentity = TestIdentity("client")
        val pins = PinSource { listOf(spkiFingerprint(serverIdentity.certificate.publicKey.encoded)) }
        val protocolExecutor = Executors.newSingleThreadExecutor()
        TestTlsServer(TestServerKeyManager(serverIdentity), AcceptAnyTrustManager()).use { server ->
            val factory =
                SslClientFactory(clientIdentity.keyManager, PinningTrustManager(pins), JvmConscryptSessionTicketDisabler())
            val acceptedControl = server.acceptSocket()
            val controlStream = factory.connect(factory.createSocket(), InetAddress.getByName("127.0.0.1"), server.port)
            val peerControl = SslSocketByteStream(acceptedControl.get())
            val acceptedMedia = server.acceptSocket()
            val mediaStream = factory.connect(factory.createSocket(), InetAddress.getByName("127.0.0.1"), server.port)
            val peerMedia = SslSocketByteStream(acceptedMedia.get())
            val client = ByteStreamSession(controlStream, Clock.systemUTC(), Dispatchers.IO)
            val peer = ByteStreamSession(peerControl, Clock.systemUTC(), Dispatchers.IO)
            val peerScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            val sender =
                FileSender(
                    client,
                    FilesScheduler(client, protocolExecutor.asCoroutineDispatcher()),
                    SourceFileReader { ZeroStream(TRANSFER_BYTES) },
                    Dispatchers.IO,
                    protocolExecutor.asCoroutineDispatcher(),
                )
            val mediaExecutor = Executors.newCachedThreadPool()
            try {
                return runBlocking {
                    withTimeout(SCENARIO_TIMEOUT) {
                        client.state.first { it is ConnectionState.Ready }
                        peer.state.first { it is ConnectionState.Ready }
                        peer
                            .receive(Channel.CHANNEL_FILES)
                            .onEach { envelope ->
                                if (envelope.hasFileOffer()) {
                                    peer.send(Channel.CHANNEL_FILES) { fileAccept = fileAccept { id = envelope.fileOffer.id } }
                                }
                            }.launchIn(peerScope)
                        val baseline = streamFrames(mediaExecutor, mediaStream, peerMedia)
                        val state = sender.send(SendRequest(TRANSFER_ID, "synthetic", "big.bin", "application/octet-stream"))
                        state.first { it is SenderState.Sending }
                        val saturated = streamFrames(mediaExecutor, mediaStream, peerMedia)
                        val senderState = state.value
                        peer.send(Channel.CHANNEL_FILES) {
                            fileCancel =
                                fileCancel {
                                    id = TRANSFER_ID
                                    reason = TransferReason.TRANSFER_REASON_USER_CANCELLED
                                }
                        }
                        ScenarioResult(baseline, saturated, senderState)
                    }
                }
            } finally {
                sender.close()
                peerScope.cancel()
                mediaExecutor.shutdownNow()
                runCatching { client.close() }
                runCatching { peer.close() }
                runCatching { mediaStream.closeAbruptly() }
                runCatching { peerMedia.closeAbruptly() }
                protocolExecutor.shutdownNow()
            }
        }
    }

    /** Sends [FRAME_COUNT] frames at 30 fps over [from]; returns each frame's delivery delay in microseconds at [to]. */
    private fun streamFrames(
        executor: java.util.concurrent.ExecutorService,
        from: ByteStream,
        to: ByteStream,
    ): List<Long> {
        val clock = TimeSource.Monotonic
        val origin = clock.markNow()
        val sentAtNanos = LongArray(FRAME_COUNT)
        val delays = ConcurrentLinkedQueue<Long>()
        val received = AtomicLong()
        val reader =
            executor.submit {
                val input = DataInputStream(to.input)
                repeat(FRAME_COUNT) {
                    val frame = MediaMessage.parseFrom(readFrame(input)).mediaFrame
                    val arrivedAtNanos = origin.elapsedNow().inWholeNanoseconds
                    delays.add((arrivedAtNanos - sentAtNanos[frame.pts.toInt()]) / NANOS_PER_MICRO)
                    received.incrementAndGet()
                }
            }
        repeat(FRAME_COUNT) { index ->
            val dueNanos = index * FRAME_INTERVAL_NANOS
            while (origin.elapsedNow().inWholeNanoseconds < dueNanos) Thread.sleep(0, SLEEP_NANOS)
            val body =
                mediaMessage {
                    mediaFrame =
                        mediaFrame {
                            pts = index.toLong()
                            data = ByteString.copyFrom(ByteArray(FRAME_PAYLOAD_BYTES))
                        }
                }.toByteArray()
            sentAtNanos[index] = origin.elapsedNow().inWholeNanoseconds
            from.output.write(ByteBuffer.allocate(LENGTH_PREFIX_BYTES + body.size).putInt(body.size).put(body).array())
            from.output.flush()
        }
        reader.get(READ_TIMEOUT_SECONDS, java.util.concurrent.TimeUnit.SECONDS)
        return delays.toList()
    }

    private fun readFrame(input: DataInputStream): ByteArray {
        val body = ByteArray(input.readInt())
        input.readFully(body)
        return body
    }

    private class ScenarioResult(
        val baselineMicros: List<Long>,
        val saturatedMicros: List<Long>,
        val senderState: SenderState,
    )

    private class ZeroStream(
        private var remaining: Long,
    ) : InputStream() {
        override fun read(): Int = if (remaining-- > 0) 0 else -1

        override fun read(
            buffer: ByteArray,
            offset: Int,
            length: Int,
        ): Int {
            if (remaining <= 0) return -1
            val count = minOf(length.toLong(), remaining).toInt()
            buffer.fill(0, offset, offset + count)
            remaining -= count
            return count
        }
    }

    private companion object {
        const val TRANSFER_ID = "e60-07"
        const val TRANSFER_BYTES = 8L shl 30
        const val FRAME_COUNT = 240
        const val FRAME_PAYLOAD_BYTES = 4096
        const val FRAME_INTERVAL_NANOS = 33_333_333L
        const val SLEEP_NANOS = 200_000
        const val NANOS_PER_MICRO = 1_000L
        const val LENGTH_PREFIX_BYTES = 4
        const val WITHIN_BASELINE_MICROS = 10_000L
        const val P95_BUDGET_MICROS = 120_000L
        const val READ_TIMEOUT_SECONDS = 30L
        val SCENARIO_TIMEOUT = 120.seconds
    }
}
