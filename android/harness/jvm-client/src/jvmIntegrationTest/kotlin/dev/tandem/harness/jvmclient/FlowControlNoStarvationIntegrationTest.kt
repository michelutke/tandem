package dev.tandem.harness.jvmclient

import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.PinningTrustManager
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.ByteStreamSession
import dev.tandem.core.transport.TandemSession
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
import dev.tandem.protocol.v1.TransferReason
import dev.tandem.protocol.v1.fileAccept
import dev.tandem.protocol.v1.fileCancel
import dev.tandem.protocol.v1.notificationPosted
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.InputStream
import java.net.InetAddress
import java.time.Clock
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource

/**
 * E40-15 tdd: integration: noStarvation_notifyDuringSaturatingFilesTransfer_p95Under100ms and
 * noStarvation_notifyBurstsAt20Hz_filesThroughputNonZeroEverySecond.
 *
 * The real [FileSender]/[FilesScheduler] (E40-03) push a synthetic 8 GiB file (long enough that 220 ticks at 20 Hz land mid-transfer) through a real
 * [ByteStreamSession] (real `ChannelMultiplexer` credit ledgers, E11-07/E11-08) over a real
 * Conscrypt mTLS loopback socket to an in-process [ByteStreamSession] peer standing in for the
 * Mac server (no app launch). NOTIFY frames are sent at 20 Hz while the FILES transfer is in the
 * `Sending` state and timestamped on one monotonic clock, so latency is arrival minus send.
 */
class FlowControlNoStarvationIntegrationTest {
    @Test
    fun noStarvation_notifyDuringSaturatingFilesTransfer_p95Under100ms() {
        val result = runScenario(framesPerTick = 1)

        assertEquals(SAMPLE_TICKS, result.latenciesMillis.size)
        val p95 = NearestRankPercentile.p95(result.latenciesMillis)
        assertTrue(p95 < P95_BUDGET_MILLIS, "NOTIFY p95 was $p95 ms")
        assertTrue(result.latenciesMillis.max() < MAX_BUDGET_MILLIS, "NOTIFY max was ${result.latenciesMillis.max()} ms")
    }

    @Test
    fun noStarvation_notifyBurstsAt20Hz_filesThroughputNonZeroEverySecond() {
        val result = runScenario(framesPerTick = BURST_FRAMES)

        assertEquals(SAMPLE_TICKS * BURST_FRAMES, result.latenciesMillis.size)
        assertTrue(result.windowChunkCounts.size >= MIN_WINDOWS, "only ${result.windowChunkCounts.size} windows measured")
        assertTrue(result.windowChunkCounts.all { it > 0 }, "FILES chunks per 1 s window: ${result.windowChunkCounts}")
    }

    private fun runScenario(framesPerTick: Int): ScenarioResult {
        HarnessConscryptProvider.ensureInstalled()
        val serverIdentity = TestIdentity("server")
        val clientIdentity = TestIdentity("client")
        val pins = PinSource { listOf(spkiFingerprint(serverIdentity.certificate.publicKey.encoded)) }
        val protocolExecutor = Executors.newSingleThreadExecutor()
        TestTlsServer(TestServerKeyManager(serverIdentity), AcceptAnyTrustManager()).use { server ->
            val accepted = server.acceptSocket()
            val factory =
                SslClientFactory(clientIdentity.keyManager, PinningTrustManager(pins), JvmConscryptSessionTicketDisabler())
            val clientStream = factory.connect(factory.createSocket(), InetAddress.getByName("127.0.0.1"), server.port)
            val serverStream = SslSocketByteStream(accepted.get())
            val client = ByteStreamSession(clientStream, Clock.systemUTC(), Dispatchers.IO)
            val peer = ByteStreamSession(serverStream, Clock.systemUTC(), Dispatchers.IO)
            val peerScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            val sender =
                FileSender(
                    client,
                    FilesScheduler(client, protocolExecutor.asCoroutineDispatcher()),
                    SourceFileReader { ZeroStream(TRANSFER_BYTES) },
                    Dispatchers.IO,
                    protocolExecutor.asCoroutineDispatcher(),
                )
            try {
                return runBlocking {
                    withTimeout(SCENARIO_TIMEOUT) {
                        client.state.first { it is ConnectionState.Ready }
                        peer.state.first { it is ConnectionState.Ready }
                        measure(client, peer, peerScope, sender, framesPerTick)
                    }
                }
            } finally {
                sender.close()
                peerScope.cancel()
                runCatching { client.close() }
                runCatching { peer.close() }
                protocolExecutor.shutdownNow()
            }
        }
    }

    private suspend fun measure(
        client: TandemSession,
        peer: TandemSession,
        peerScope: CoroutineScope,
        sender: FileSender,
        framesPerTick: Int,
    ): ScenarioResult {
        val clock = TimeSource.Monotonic
        val chunkArrivals = ConcurrentLinkedQueue<TimeSource.Monotonic.ValueTimeMark>()
        val notifyLatencies = ConcurrentLinkedQueue<Long>()
        val sentMarks = ConcurrentHashMap<String, TimeSource.Monotonic.ValueTimeMark>()
        peer
            .receive(Channel.CHANNEL_FILES)
            .onEach { envelope ->
                when {
                    envelope.hasFileOffer() -> peer.send(Channel.CHANNEL_FILES) { fileAccept = fileAccept { id = envelope.fileOffer.id } }
                    envelope.hasFileChunk() -> chunkArrivals.add(clock.markNow())
                }
            }.launchIn(peerScope)
        peer
            .receive(Channel.CHANNEL_NOTIFY)
            .onEach { envelope ->
                val sentAt = sentMarks.remove(envelope.notificationPosted.key)
                if (sentAt != null) notifyLatencies.add(sentAt.elapsedNow().inWholeMilliseconds)
            }.launchIn(peerScope)

        val state = sender.send(SendRequest(TRANSFER_ID, "synthetic", "big.bin", "application/octet-stream"))
        state.first { it is SenderState.Sending }
        val start = clock.markNow()
        repeat(SAMPLE_TICKS) { tick ->
            delay((TICK * tick) - start.elapsedNow())
            repeat(framesPerTick) { index ->
                val key = "$tick-$index"
                sentMarks[key] = clock.markNow()
                client.send(Channel.CHANNEL_NOTIFY) {
                    notificationPosted = notificationPosted { this.key = key }
                }
            }
        }
        val windowEnd = start.elapsedNow()
        val stillSending = state.value is SenderState.Sending
        peer.send(Channel.CHANNEL_FILES) {
            fileCancel =
                fileCancel {
                    id = TRANSFER_ID
                    reason = TransferReason.TRANSFER_REASON_USER_CANCELLED
                }
        }
        while (notifyLatencies.size < SAMPLE_TICKS * framesPerTick) delay(10.milliseconds)
        assertTrue(stillSending, "FILES transfer finished before the NOTIFY sampling window ended")
        val windows = (0 until windowEnd.inWholeSeconds.toInt()).map { second ->
            chunkArrivals.count { mark -> (mark - start).let { it >= second.seconds && it < (second + 1).seconds } }
        }
        return ScenarioResult(notifyLatencies.toList(), windows)
    }

    private class ScenarioResult(
        val latenciesMillis: List<Long>,
        val windowChunkCounts: List<Int>,
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
        const val TRANSFER_ID = "e40-15"
        const val TRANSFER_BYTES = 8L shl 30
        const val SAMPLE_TICKS = 220
        const val BURST_FRAMES = 4
        const val MIN_WINDOWS = 10
        const val P95_BUDGET_MILLIS = 100L
        const val MAX_BUDGET_MILLIS = 500L
        val TICK = 50.milliseconds
        val SCENARIO_TIMEOUT = 120.seconds
    }
}
