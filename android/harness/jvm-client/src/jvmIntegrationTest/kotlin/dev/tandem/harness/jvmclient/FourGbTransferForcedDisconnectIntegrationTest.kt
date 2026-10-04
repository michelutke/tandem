package dev.tandem.harness.jvmclient

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.PinSource
import dev.tandem.core.crypto.PinningTrustManager
import dev.tandem.core.crypto.spkiFingerprint
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.ByteStream
import dev.tandem.core.transport.ByteStreamSession
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.tls.SslClientFactory
import dev.tandem.core.transport.tls.SslSocketByteStream
import dev.tandem.feature.files.DownloadsPublisher
import dev.tandem.feature.files.FileReceiver
import dev.tandem.feature.files.FileSender
import dev.tandem.feature.files.FileTransferStore
import dev.tandem.feature.files.FilesScheduler
import dev.tandem.feature.files.RetainedSends
import dev.tandem.feature.files.SendRequest
import dev.tandem.feature.files.SenderState
import dev.tandem.feature.files.SourceFileReader
import dev.tandem.feature.files.TransferStore
import dev.tandem.harness.jvmclient.testserver.AcceptAnyTrustManager
import dev.tandem.harness.jvmclient.testserver.TestIdentity
import dev.tandem.harness.jvmclient.testserver.TestServerKeyManager
import dev.tandem.harness.jvmclient.testserver.TestTlsServer
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.FileOffer
import dev.tandem.protocol.v1.fileAccept
import dev.tandem.protocol.v1.fileOffer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.io.InputStream
import java.net.InetAddress
import java.security.MessageDigest
import java.time.Clock
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/**
 * E40-14 tdd: integration: transferHarness_phoneToMac256MiBAbruptCloseAtHalf_resumesAndShaMatches,
 * transferHarness_macToPhone256MiBAbruptCloseAtHalf_resumesAndShaMatches and
 * transferHarness_resumeAfterAbruptClose_resentBytesAtMostFourMiB.
 *
 * The real [FileSender] (E40-03) and [FileReceiver] (E40-05) with resume (E40-08) run over two real
 * [ByteStreamSession]s on a real Conscrypt mTLS loopback socket (no app launch). The transfer is a
 * synthetic deterministic 256 MiB source and a hashing [DownloadsPublisher]; the sender's raw
 * socket is reset (`closeAbruptly`) once the receiver's `.part` file passes 50 %, both ends
 * reconnect on a fresh socket and the receiver resumes from its retained `.part` file.
 */
class FourGbTransferForcedDisconnectIntegrationTest {
    @TempDir
    lateinit var staging: File

    @Test
    fun transferHarness_phoneToMac256MiBAbruptCloseAtHalf_resumesAndShaMatches() {
        val result = runScenario(senderIsClient = true)

        assertResumedAndMatches(result)
    }

    @Test
    fun transferHarness_macToPhone256MiBAbruptCloseAtHalf_resumesAndShaMatches() {
        val result = runScenario(senderIsClient = false)

        assertResumedAndMatches(result)
    }

    @Test
    fun transferHarness_resumeAfterAbruptClose_resentBytesAtMostFourMiB() {
        val result = runScenario(senderIsClient = true)

        assertTrue(result.resumeFromOffset > 0, "resume fromOffset was ${result.resumeFromOffset}")
        assertTrue(result.resentBytes <= MAX_RESENT_BYTES, "re-sent ${result.resentBytes} bytes")
    }

    private fun assertResumedAndMatches(result: ScenarioResult) {
        assertTrue(result.resumeFromOffset > 0, "resume fromOffset was ${result.resumeFromOffset}")
        assertTrue(result.resumeFromOffset < TRANSFER_BYTES, "resume fromOffset was ${result.resumeFromOffset}")
        assertEquals(TRANSFER_BYTES, result.publishedBytes)
        assertArrayEquals(result.sourceSha256, result.publishedSha256)
    }

    private fun runScenario(senderIsClient: Boolean): ScenarioResult {
        HarnessConscryptProvider.ensureInstalled()
        val serverIdentity = TestIdentity("server")
        val clientIdentity = TestIdentity("client")
        val pins = PinSource { listOf(spkiFingerprint(serverIdentity.certificate.publicKey.encoded)) }
        val factory = SslClientFactory(clientIdentity.keyManager, PinningTrustManager(pins), JvmConscryptSessionTicketDisabler())
        val senderFingerprint =
            spkiFingerprint((if (senderIsClient) clientIdentity else serverIdentity).certificate.publicKey.encoded)
        val protocolExecutor = Executors.newSingleThreadExecutor()
        val peerScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val store = CountingTransferStore(FileTransferStore(staging, Clock.systemUTC()))
        val reader = SourceFileReader { syntheticSource(TRANSFER_BYTES) }
        val published = CompletableFuture<Published>()
        val publisher = hashingPublisher(published)
        val retained = RetainedSends()
        val opened = mutableListOf<Link>()
        try {
            TestTlsServer(TestServerKeyManager(serverIdentity), AcceptAnyTrustManager()).use { server ->
                fun connect(): Link = connectLink(server, factory).also { opened += it }

                fun newSender(link: Link): FileSender {
                    val session = if (senderIsClient) link.client else link.server
                    return FileSender(
                        session,
                        FilesScheduler(session, protocolExecutor.asCoroutineDispatcher()),
                        reader,
                        Dispatchers.IO,
                        protocolExecutor.asCoroutineDispatcher(),
                        retained,
                    )
                }

                fun newReceiver(link: Link): FileReceiver {
                    val session = if (senderIsClient) link.server else link.client
                    return FileReceiver(
                        session,
                        store,
                        publisher,
                        senderFingerprint,
                        Clock.systemUTC(),
                        Dispatchers.IO,
                        protocolExecutor.asCoroutineDispatcher(),
                    )
                }

                val sourceSha256 = sha256Of(syntheticSource(TRANSFER_BYTES))
                return runBlocking {
                    withTimeout(SCENARIO_TIMEOUT) {
                        val first = connect()
                        val firstSender = newSender(first)
                        val firstReceiver = newReceiver(first)
                        firstReceiver.expect(offer(sourceSha256))
                        val state = firstSender.send(SendRequest(TRANSFER_ID, "synthetic", "big.bin", MIME))
                        state.first { it is SenderState.Offered }
                        (if (senderIsClient) first.server else first.client).send(Channel.CHANNEL_FILES) {
                            fileAccept = fileAccept { id = TRANSFER_ID }
                        }
                        while (store.appendedBytes.get() < TRANSFER_BYTES / 2) delay(POLL)
                        (if (senderIsClient) first.clientStream else first.serverStream).closeAbruptly()
                        awaitQuiescent(store)
                        firstSender.close()
                        firstReceiver.close()
                        val persistedBeforeResume = store.appendedBytes.get()

                        val second = connect()
                        val secondSender = newSender(second)
                        val secondReceiver = newReceiver(second)
                        secondReceiver.resumeRetained()
                        val outcome = withContext(Dispatchers.IO) { published.get() }
                        secondSender.close()
                        secondReceiver.close()
                        val resumeFromOffset = store.lastTruncatedLength.get()
                        ScenarioResult(
                            sourceSha256 = sourceSha256,
                            publishedSha256 = outcome.sha256,
                            publishedBytes = outcome.bytes,
                            resumeFromOffset = resumeFromOffset,
                            resentBytes = persistedBeforeResume - resumeFromOffset,
                        )
                    }
                }
            }
        } finally {
            peerScope.cancel()
            opened.forEach { it.close() }
            protocolExecutor.shutdownNow()
        }
    }

    private fun connectLink(
        server: TestTlsServer,
        factory: SslClientFactory,
    ): Link {
        val accepted = server.acceptSocket()
        val clientStream = factory.connect(factory.createSocket(), InetAddress.getByName("127.0.0.1"), server.port)
        val serverStream = SslSocketByteStream(accepted.get())
        val link =
            Link(
                clientStream,
                serverStream,
                ByteStreamSession(clientStream, Clock.systemUTC(), Dispatchers.IO),
                ByteStreamSession(serverStream, Clock.systemUTC(), Dispatchers.IO),
            )
        runBlocking {
            link.client.state.first { it is ConnectionState.Ready }
            link.server.state.first { it is ConnectionState.Ready }
        }
        return link
    }

    private fun offer(sha256: ByteArray): FileOffer =
        fileOffer {
            id = TRANSFER_ID
            name = "big.bin"
            size = TRANSFER_BYTES
            mime = MIME
            this.sha256 = ByteString.copyFrom(sha256)
        }

    private suspend fun awaitQuiescent(store: CountingTransferStore) {
        var last = -1L
        while (store.appendedBytes.get() != last) {
            last = store.appendedBytes.get()
            delay(QUIESCENT)
        }
    }

    private fun hashingPublisher(published: CompletableFuture<Published>) =
        DownloadsPublisher { _, _, content ->
            val digest = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(BUFFER_BYTES)
            var bytes = 0L
            while (true) {
                val read = content.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
                bytes += read
            }
            published.complete(Published(digest.digest(), bytes))
        }

    private fun sha256Of(input: InputStream): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(BUFFER_BYTES)
        input.use {
            while (true) {
                val read = it.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest()
    }

    private class Link(
        val clientStream: ByteStream,
        val serverStream: ByteStream,
        val client: TandemSession,
        val server: TandemSession,
    ) {
        fun close() {
            runCatching { client.close() }
            runCatching { server.close() }
        }
    }

    private class Published(
        val sha256: ByteArray,
        val bytes: Long,
    )

    private class ScenarioResult(
        val sourceSha256: ByteArray,
        val publishedSha256: ByteArray,
        val publishedBytes: Long,
        val resumeFromOffset: Long,
        val resentBytes: Long,
    )

    private class CountingTransferStore(
        private val delegate: TransferStore,
    ) : TransferStore by delegate {
        val appendedBytes = AtomicLong()
        val lastTruncatedLength = AtomicLong()

        override fun append(
            id: String,
            data: ByteArray,
        ) {
            delegate.append(id, data)
            appendedBytes.addAndGet(data.size.toLong())
        }

        override fun truncate(
            id: String,
            length: Long,
        ) {
            delegate.truncate(id, length)
            lastTruncatedLength.set(length)
        }
    }

    private companion object {
        const val TRANSFER_ID = "e40-14"
        const val MIME = "application/octet-stream"
        const val TRANSFER_BYTES = 256L shl 20
        const val MAX_RESENT_BYTES = 4L shl 20
        const val BUFFER_BYTES = 262_144
        val POLL = 5.milliseconds
        val QUIESCENT = 200.milliseconds
        val SCENARIO_TIMEOUT = 120.seconds

        fun syntheticSource(length: Long): InputStream = DeterministicStream(length)
    }

    /** Position-addressable pseudo-random bytes: `skip` is O(1) and the same bytes come back on every open. */
    private class DeterministicStream(
        private val length: Long,
    ) : InputStream() {
        private var position = 0L

        override fun read(): Int = if (position >= length) -1 else byteAt(position++).toInt() and 0xFF

        override fun read(
            buffer: ByteArray,
            offset: Int,
            count: Int,
        ): Int {
            if (position >= length) return -1
            val read = minOf(count.toLong(), length - position).toInt()
            for (index in 0 until read) buffer[offset + index] = byteAt(position + index)
            position += read
            return read
        }

        override fun skip(count: Long): Long {
            val skipped = minOf(maxOf(count, 0), length - position)
            position += skipped
            return skipped
        }

        private fun byteAt(index: Long): Byte {
            var mixed = (index ushr 3) * GOLDEN + SEED
            mixed = (mixed xor (mixed ushr 30)) * MIX_A
            mixed = (mixed xor (mixed ushr 27)) * MIX_B
            mixed = mixed xor (mixed ushr 31)
            return (mixed ushr (((index and 7).toInt()) * 8)).toByte()
        }

        private companion object {
            const val GOLDEN = -7046029254386353131L
            const val SEED = 0x1234_5678L
            const val MIX_A = -4658895280553007687L
            const val MIX_B = -7723592293110705685L
        }
    }
}
