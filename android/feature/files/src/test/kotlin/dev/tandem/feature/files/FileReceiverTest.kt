package dev.tandem.feature.files

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.FileOffer
import dev.tandem.protocol.v1.TransferReason
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.fileChunk
import dev.tandem.protocol.v1.fileComplete
import dev.tandem.protocol.v1.fileOffer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
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

// E40-05 tdd (docs/planning/backlog/phase-4.yaml): FakeTandemSession, @TempDir-backed store, a
// recording publisher and a store that throws ENOSPC at a given offset; dispatchers share runTest's scheduler.
@OptIn(ExperimentalCoroutinesApi::class)
class FileReceiverTest {
    @TempDir
    lateinit var dir: File

    private val session = FakeTandemSession()
    private val publisher = RecordingPublisher()

    @Test
    fun androidReceiver_matchingHash_publishedOnceAndPartFileDeleted() =
        runTest {
            val content = ByteArray(300_000) { (it % 251).toByte() }
            val store = FailingStore(FileTransferStore(dir))
            val receiver = newReceiver(store)
            receiver.expect(offer("a", "../report.pdf", content))
            runCurrent()

            chunks("a", content)
            complete("a")

            assertEquals(1, publisher.published.size)
            assertEquals("report.pdf", publisher.published.single().name)
            assertArrayEquals(content, publisher.published.single().bytes)
            assertTrue(partFiles().isEmpty())
            assertTrue(session.sentFrames.isEmpty())
            assertEquals(0, receiver.activeCount)
        }

    @Test
    fun androidReceiver_hashMismatch_partDeletedNothingPublishedAndCancelSent() =
        runTest {
            val content = ByteArray(1000) { 7 }
            val receiver = newReceiver(FileTransferStore(dir))
            receiver.expect(offer("a", "x.bin", content, sha = ByteArray(32)))
            runCurrent()

            chunks("a", content)
            complete("a")

            assertTrue(publisher.published.isEmpty())
            assertTrue(partFiles().isEmpty())
            val cancel = session.sentFrames.single().fileCancel
            assertEquals("a", cancel.id)
            assertEquals(TransferReason.TRANSFER_REASON_HASH_MISMATCH, cancel.reason)
        }

    @Test
    fun androidReceiver_enospcDuringWrite_partDeletedAndInsufficientSpaceCancelSent() =
        runTest {
            val content = ByteArray(600_000)
            val store = FailingStore(FileTransferStore(dir), failAtOffset = CHUNK.toLong())
            val receiver = newReceiver(store)
            receiver.expect(offer("a", "x.bin", content))
            runCurrent()

            chunks("a", content)

            assertTrue(publisher.published.isEmpty())
            assertTrue(partFiles().isEmpty())
            assertCancel(TransferReason.TRANSFER_REASON_INSUFFICIENT_SPACE)
        }

    @Test
    fun androidReceiver_chunkBeyondOfferedSize_protocolViolationCancelAndPartDeleted() =
        runTest {
            val receiver = newReceiver(FileTransferStore(dir))
            receiver.expect(offer("a", "x.bin", ByteArray(10)))
            runCurrent()

            emit(chunk("a", 0, ByteArray(11)))
            runCurrent()

            assertCancel(TransferReason.TRANSFER_REASON_PROTOCOL_VIOLATION)
            assertTrue(partFiles().isEmpty())
        }

    @Test
    fun androidReceiver_chunkOffsetGap_protocolViolationCancelAndPartDeleted() =
        runTest {
            val receiver = newReceiver(FileTransferStore(dir))
            receiver.expect(offer("a", "x.bin", ByteArray(100)))
            runCurrent()

            emit(chunk("a", 10, ByteArray(10)))
            runCurrent()

            assertCancel(TransferReason.TRANSFER_REASON_PROTOCOL_VIOLATION)
            assertTrue(partFiles().isEmpty())
        }

    @Test
    fun androidReceiver_chunkOverlappingEarlierBytes_protocolViolationCancel() =
        runTest {
            val receiver = newReceiver(FileTransferStore(dir))
            receiver.expect(offer("a", "x.bin", ByteArray(100)))
            runCurrent()

            emit(chunk("a", 0, ByteArray(20)))
            emit(chunk("a", 10, ByteArray(20)))
            runCurrent()

            assertCancel(TransferReason.TRANSFER_REASON_PROTOCOL_VIOLATION)
            assertTrue(partFiles().isEmpty())
        }

    @Test
    fun androidReceiver_chunkOverCap_protocolViolationCancel() =
        runTest {
            val receiver = newReceiver(FileTransferStore(dir))
            receiver.expect(offer("a", "x.bin", ByteArray(CHUNK + 1)))
            runCurrent()

            emit(chunk("a", 0, ByteArray(CHUNK + 1)))
            runCurrent()

            assertCancel(TransferReason.TRANSFER_REASON_PROTOCOL_VIOLATION)
        }

    @Test
    fun androidReceiver_completeBeforeAllBytes_protocolViolationNothingPublished() =
        runTest {
            val receiver = newReceiver(FileTransferStore(dir))
            receiver.expect(offer("a", "x.bin", ByteArray(100)))
            runCurrent()

            emit(chunk("a", 0, ByteArray(50)))
            complete("a")

            assertTrue(publisher.published.isEmpty())
            assertCancel(TransferReason.TRANSFER_REASON_PROTOCOL_VIOLATION)
            assertTrue(partFiles().isEmpty())
        }

    @Test
    fun androidReceiver_publishFails_ioErrorCancelAndPartDeleted() =
        runTest {
            val content = ByteArray(10)
            publisher.failWith = IOException()
            val receiver = newReceiver(FileTransferStore(dir))
            receiver.expect(offer("a", "x.bin", content))
            runCurrent()

            chunks("a", content)
            complete("a")

            assertCancel(TransferReason.TRANSFER_REASON_IO_ERROR)
            assertTrue(partFiles().isEmpty())
        }

    @Test
    fun androidReceiver_peerCancel_partDeletedNothingPublished() =
        runTest {
            val receiver = newReceiver(FileTransferStore(dir))
            receiver.expect(offer("a", "x.bin", ByteArray(100)))
            runCurrent()
            emit(chunk("a", 0, ByteArray(10)))
            runCurrent()

            emit(
                envelope {
                    channel = Channel.CHANNEL_FILES
                    fileCancel =
                        dev.tandem.protocol.v1
                            .fileCancel { id = "a" }
                },
            )
            runCurrent()

            assertTrue(partFiles().isEmpty())
            assertEquals(0, receiver.activeCount)
            assertTrue(session.sentFrames.isEmpty())
        }

    @Test
    fun androidReceiver_unknownTransferChunk_unknownTransferRejectSent() =
        runTest {
            newReceiver(FileTransferStore(dir))

            emit(chunk("zzz", 0, ByteArray(1)))
            runCurrent()

            assertEquals(
                TransferReason.TRANSFER_REASON_UNKNOWN_TRANSFER,
                session.sentFrames
                    .single()
                    .fileReject.reason,
            )
        }

    @Test
    fun androidReceiver_macUnpaired_retainedPartFilesDeleted() =
        runTest {
            val receiver = newReceiver(FileTransferStore(dir))
            receiver.expect(offer("a", "x.bin", ByteArray(100)))
            runCurrent()
            emit(chunk("a", 0, ByteArray(10)))
            runCurrent()
            assertEquals(1, partFiles().size)

            receiver.purgeAll(SpkiFingerprint(ByteArray(32)))

            assertTrue(partFiles().isEmpty())
            assertEquals(0, receiver.activeCount)
        }

    private fun TestScope.newReceiver(store: TransferStore): FileReceiver {
        val dispatcher = StandardTestDispatcher(testScheduler)
        return FileReceiver(session, store, publisher, dispatcher, dispatcher)
    }

    private fun partFiles(): List<File> = dir.listFiles { f -> f.name.endsWith(".part") }.orEmpty().toList()

    private fun assertCancel(reason: TransferReason) {
        assertEquals(
            reason,
            session.sentFrames
                .first()
                .fileCancel.reason,
        )
    }

    private fun TestScope.chunks(
        id: String,
        content: ByteArray,
    ) {
        content.toList().chunked(CHUNK).fold(0) { offset, part ->
            emit(chunk(id, offset.toLong(), part.toByteArray()))
            offset + part.size
        }
        runCurrent()
    }

    private fun TestScope.complete(id: String) {
        emit(
            envelope {
                channel = Channel.CHANNEL_FILES
                fileComplete = fileComplete { this.id = id }
            },
        )
        runCurrent()
    }

    private fun emit(envelope: Envelope) = session.emitIncoming(envelope)

    private fun chunk(
        id: String,
        offset: Long,
        bytes: ByteArray,
    ): Envelope =
        envelope {
            channel = Channel.CHANNEL_FILES
            fileChunk =
                fileChunk {
                    this.id = id
                    seq = offset / CHUNK
                    this.offset = offset
                    data = ByteString.copyFrom(bytes)
                }
        }

    private fun offer(
        id: String,
        name: String,
        content: ByteArray,
        sha: ByteArray = MessageDigest.getInstance("SHA-256").digest(content),
    ): FileOffer =
        fileOffer {
            this.id = id
            this.name = name
            size = content.size.toLong()
            mime = "application/pdf"
            sha256 = ByteString.copyFrom(sha)
        }

    private class Published(
        val name: String,
        val bytes: ByteArray,
    )

    private class RecordingPublisher : DownloadsPublisher {
        val published = mutableListOf<Published>()
        var failWith: IOException? = null

        override fun publish(
            name: String,
            mime: String,
            content: InputStream,
        ) {
            failWith?.let { throw it }
            published += Published(name, content.readBytes())
        }
    }

    private class FailingStore(
        private val delegate: TransferStore,
        private val failAtOffset: Long = -1,
    ) : TransferStore by delegate {
        private val written = mutableMapOf<String, Long>()

        override fun append(
            id: String,
            data: ByteArray,
        ) {
            val offset = written.getOrDefault(id, 0L)
            if (offset == failAtOffset) throw InsufficientSpaceException()
            delegate.append(id, data)
            written[id] = offset + data.size
        }
    }

    private companion object {
        const val CHUNK = 262_144
    }
}
