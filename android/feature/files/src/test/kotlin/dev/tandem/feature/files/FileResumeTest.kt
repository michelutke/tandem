package dev.tandem.feature.files

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.testing.TestClock
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.TransferReason
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.fileAccept
import dev.tandem.protocol.v1.fileResumeRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import java.time.Instant
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.seconds

// E40-08 tdd (docs/planning/backlog/phase-4.yaml): a real FileSender and FileReceiver joined by
// frame forwarding between FakeTandemSessions; "severing" drops undelivered frames, and the
// reconnect is a fresh session pair around the same TransferStore and RetainedSends.
@OptIn(ExperimentalCoroutinesApi::class)
class FileResumeTest {
    @TempDir
    lateinit var dir: File

    private val peer = SpkiFingerprint(ByteArray(32) { 1 })
    private val publisher = RecordingPublisher()
    private val retained = RetainedSends()

    @Test
    fun androidResume_severedAt40MiB_resumeRequestFromOffset40MiB() =
        runTest {
            val source = source(64 * MIB)
            val store = store()
            val first = connect(store)
            first.sendOffered(source)
            first.deliverChunks(CHUNKS_40_MIB)
            first.sever()
            store.append(ID, ByteArray(1000))

            val second = connect(store)
            second.receiver.resumeRetained()
            runCurrent()

            val request =
                second.receiverSession.sentFrames
                    .single()
                    .fileResumeRequest
            assertEquals(ID, request.id)
            assertEquals(40L * MIB, request.fromOffset)
            second.forwardResumeRequest()
            val firstResumed =
                second.senderSession.sentFrames
                    .first { it.hasFileChunk() }
                    .fileChunk
            assertEquals(40L * MIB / CHUNK, firstResumed.seq)
            assertEquals(40L * MIB, firstResumed.offset)
        }

    @Test
    fun androidResume_resumedTransfer_publishedSha256MatchesSource() =
        runTest {
            val source = source(3 * MIB + 17)
            val store = store()
            val first = connect(store)
            first.sendOffered(source)
            first.deliverChunks(5)
            first.sever()

            val second = connect(store)
            second.receiver.resumeRetained()
            runCurrent()
            second.forwardResumeRequest()
            second.deliverResumedTransfer()

            val published = publisher.published.single()
            assertArrayEquals(sha256(source.readBytes()), sha256(published))
            assertEquals(source.length().toInt(), published.size)
            assertTrue(store.ids().isEmpty())
        }

    @Test
    fun androidResume_afterResume_resentBytesAtMostCreditWindowPlusOneChunk() =
        runTest {
            val source = source(3 * MIB)
            val store = store()
            val first = connect(store)
            first.sendOffered(source)
            first.deliverChunks(4)
            first.sever()
            store.append(ID, ByteArray(CHUNK - 1))
            val retainedBytes = store.length(ID)

            val second = connect(store)
            second.receiver.resumeRetained()
            runCurrent()
            second.forwardResumeRequest()

            val fromOffset =
                second.receiverSession.sentFrames
                    .single()
                    .fileResumeRequest.fromOffset
            val resent = retainedBytes - fromOffset
            assertTrue(resent <= CHUNK, "resent $resent")
            assertEquals(
                fromOffset,
                second.senderSession.sentFrames
                    .first { it.hasFileChunk() }
                    .fileChunk.offset,
            )
        }

    @Test
    fun androidResume_unknownTransferId_fileRejectUnknownTransfer() =
        runTest {
            val connection = connect(store())
            connection.senderSession.emitIncoming(resumeRequest("nope", 0))
            runCurrent()

            val reject =
                connection.senderSession.sentFrames
                    .single()
                    .fileReject
            assertEquals("nope", reject.id)
            assertEquals(TransferReason.TRANSFER_REASON_UNKNOWN_TRANSFER, reject.reason)
        }

    @Test
    fun androidResume_partOlderThan24h_deletedAndNoResumeRequest() =
        runTest {
            val store = store(TestClock(testScheduler, START))
            val first = connect(store)
            first.sendOffered(source(MIB))
            first.deliverChunks(2)
            first.sever()
            advanceTimeBy(24.hours + 1.seconds)

            val second = connect(store)
            second.receiver.resumeRetained()
            runCurrent()

            assertTrue(second.receiverSession.sentFrames.isEmpty())
            assertTrue(dir.walk().none { it.name.endsWith(".part") || it.name.endsWith(".meta") })
        }

    @Test
    fun androidResume_partExactly24hOld_stillResumes() =
        runTest {
            val store = store(TestClock(testScheduler, START))
            val first = connect(store)
            first.sendOffered(source(MIB))
            first.deliverChunks(2)
            first.sever()
            advanceTimeBy(24.hours)

            val second = connect(store)
            second.receiver.resumeRetained()
            runCurrent()

            assertEquals(
                2L * CHUNK,
                second.receiverSession.sentFrames
                    .single()
                    .fileResumeRequest.fromOffset,
            )
        }

    @Test
    fun androidResume_partRetainedForOtherPeer_notResumed() =
        runTest {
            val store = store()
            val first = connect(store)
            first.sendOffered(source(MIB))
            first.deliverChunks(2)
            first.sever()

            val other = connect(store, SpkiFingerprint(ByteArray(32) { 2 }))
            other.receiver.resumeRetained()
            runCurrent()

            assertTrue(other.receiverSession.sentFrames.isEmpty())
            assertEquals(1, store.ids().size)
        }

    @Test
    fun androidResume_misalignedOrOversizedOffset_protocolViolationCancel() =
        runTest {
            val store = store()
            val first = connect(store)
            first.sendOffered(source(MIB))
            first.sever()
            val second = connect(store)

            second.senderSession.emitIncoming(resumeRequest(ID, 100))
            second.senderSession.emitIncoming(resumeRequest(ID, 2L * MIB))
            runCurrent()

            val reasons = second.senderSession.sentFrames.map { it.fileCancel.reason }
            assertEquals(List(2) { TransferReason.TRANSFER_REASON_PROTOCOL_VIOLATION }, reasons)
        }

    @Test
    fun androidResume_sourceUnreadable_fileCancelSourceUnavailable() =
        runTest {
            val source = source(MIB)
            val store = store()
            val first = connect(store)
            first.sendOffered(source)
            first.sever()
            source.delete()
            val second = connect(store)

            second.senderSession.emitIncoming(resumeRequest(ID, 0))
            runCurrent()

            assertEquals(
                TransferReason.TRANSFER_REASON_SOURCE_UNAVAILABLE,
                second.senderSession.sentFrames
                    .single()
                    .fileCancel.reason,
            )
        }

    private fun TestScope.connect(
        store: TransferStore,
        receiverPeer: SpkiFingerprint = peer,
    ): Connection {
        val senderSession = FakeTandemSession()
        val receiverSession = FakeTandemSession()
        val dispatcher = StandardTestDispatcher(testScheduler)
        val sender =
            FileSender(
                senderSession,
                FilesScheduler(senderSession, dispatcher),
                { File(it).inputStream() },
                StandardTestDispatcher(testScheduler),
                dispatcher,
                retained,
            )
        val receiver =
            FileReceiver(
                receiverSession,
                store,
                publisher,
                receiverPeer,
                TestClock(testScheduler, START),
                StandardTestDispatcher(testScheduler),
                dispatcher,
            )
        return Connection(this, sender, receiver, senderSession, receiverSession)
    }

    private class Connection(
        private val scope: TestScope,
        val sender: FileSender,
        val receiver: FileReceiver,
        val senderSession: FakeTandemSession,
        val receiverSession: FakeTandemSession,
    ) {
        private var delivered = 0

        fun sendOffered(source: File) {
            sender.send(SendRequest(ID, source.path, "file.bin", "application/octet-stream"))
            scope.runCurrent()
            val offer = senderSession.sentFrames.single().fileOffer
            receiver.expect(offer)
            scope.runCurrent()
            senderSession.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_FILES
                    fileAccept = fileAccept { id = ID }
                },
            )
            scope.runCurrent()
            delivered = 1
        }

        fun deliverChunks(count: Int) {
            senderSession.sentFrames
                .drop(delivered)
                .take(count)
                .forEach { receiverSession.emitIncoming(it) }
            scope.runCurrent()
        }

        fun sever() {
            sender.close()
            receiver.close()
            senderSession.close()
            receiverSession.close()
        }

        fun forwardResumeRequest() {
            senderSession.emitIncoming(receiverSession.sentFrames.single())
            scope.runCurrent()
        }

        fun deliverResumedTransfer() {
            senderSession.sentFrames.forEach { receiverSession.emitIncoming(it) }
            scope.runCurrent()
        }
    }

    private fun TestScope.store(clock: TestClock = TestClock(testScheduler, START)): TransferStore =
        FileTransferStore(File(dir, "rx"), clock)

    private fun source(size: Int): File =
        File(dir, "source.bin").also { file -> file.writeBytes(ByteArray(size) { (it % 251).toByte() }) }

    private fun resumeRequest(
        id: String,
        offset: Long,
    ): Envelope =
        envelope {
            channel = Channel.CHANNEL_FILES
            fileResumeRequest =
                fileResumeRequest {
                    this.id = id
                    fromOffset = offset
                }
        }

    private fun sha256(bytes: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(bytes)

    private class RecordingPublisher : DownloadsPublisher {
        val published = mutableListOf<ByteArray>()

        @Throws(IOException::class)
        override fun publish(
            name: String,
            mime: String,
            content: InputStream,
        ) {
            published += content.readBytes()
        }
    }

    private companion object {
        const val ID = "t1"
        const val MIB = 1024 * 1024
        const val CHUNK = 262_144
        const val CHUNKS_40_MIB = 160
        val START: Instant = Instant.ofEpochSecond(1_700_000_000)
    }
}
