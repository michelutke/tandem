package dev.tandem.feature.files

import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.TransferReason
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.fileAccept
import dev.tandem.protocol.v1.fileCancel
import dev.tandem.protocol.v1.fileReject
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.StateFlow
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

// E40-03 tdd (docs/planning/backlog/phase-4.yaml): message-level sender tests on FakeTandemSession
// and @TempDir fixtures; dispatchers share the runTest scheduler (E00-18).
@OptIn(ExperimentalCoroutinesApi::class)
class FileSenderTest {
    @TempDir
    lateinit var dir: File

    private val session = FakeTandemSession()

    @Test
    fun androidSender_tenMiBPlusOneByteFile_sends41ContiguousChunksThenComplete() =
        runTest {
            val file = fixture("big", ByteArray(10 * MIB + 1) { (it % 251).toByte() })
            val state = startAccepted(file)

            val chunks = session.sentFrames.filter { it.hasFileChunk() }.map { it.fileChunk }
            assertEquals(41, chunks.size)
            assertEquals((0L..40L).toList(), chunks.map { it.seq })
            assertEquals(chunks.map { it.seq * CHUNK }, chunks.map { it.offset })
            assertEquals(1, chunks.last().data.size())
            assertTrue(session.sentFrames.last().hasFileComplete())
            assertEquals(1, session.sentFrames.count { it.hasFileComplete() })
            assertEquals(SenderState.Completed, state.value)
        }

    @Test
    fun androidSender_abcFixture_offerCarriesKnownSha256() =
        runTest {
            startAccepted(fixture("abc", "abc".toByteArray()))

            val offer = session.sentFrames.first().fileOffer
            assertEquals(ABC_SHA256, offer.sha256.toByteArray().toHex())
            assertEquals(3L, offer.size)
            assertEquals("abc.txt", offer.name)
        }

    @Test
    fun androidSender_zeroByteFile_offerThenCompleteWithNoChunks() =
        runTest {
            startAccepted(fixture("empty", ByteArray(0)))

            assertEquals(
                0L,
                session.sentFrames
                    .first()
                    .fileOffer.size,
            )
            assertTrue(session.sentFrames[0].hasFileOffer())
            assertTrue(session.sentFrames[1].hasFileComplete())
            assertEquals(2, session.sentFrames.size)
        }

    @Test
    fun androidSender_fileRejectReceived_zeroChunksSentAndStateRejected() =
        runTest {
            val sender = newSender { File(it).inputStream() }
            val state = sender.send(request(fixture("abc", "abc".toByteArray())))
            runCurrent()

            session.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_FILES
                    fileReject =
                        fileReject {
                            id = ID
                            reason = TransferReason.TRANSFER_REASON_DECLINED
                        }
                },
            )
            runCurrent()

            assertEquals(1, session.sentFrames.size)
            assertEquals(SenderState.Rejected(TransferReason.TRANSFER_REASON_DECLINED), state.value)
        }

    @Test
    fun androidSender_sourceReadFailsMidTransfer_sendsFileCancelIoError() =
        runTest {
            val file = fixture("big", ByteArray(2 * MIB))
            var opens = 0
            val sender =
                newSender {
                    if (++opens == 1) File(it).inputStream() else FailingAfter(CHUNK.toInt() + 10)
                }
            val state = sender.send(request(file))
            runCurrent()
            accept()

            assertEquals(1, session.sentFrames.count { it.hasFileChunk() })
            val last = session.sentFrames.last()
            assertEquals(TransferReason.TRANSFER_REASON_IO_ERROR, last.fileCancel.reason)
            assertTrue(session.sentFrames.none { it.hasFileComplete() })
            assertEquals(SenderState.Cancelled(TransferReason.TRANSFER_REASON_IO_ERROR), state.value)
        }

    @Test
    fun androidSender_fileCancelReceivedMidTransfer_stopsSendingAndClosesReader() =
        runTest {
            val file = fixture("big", ByteArray(2 * MIB))
            var opens = 0
            var closed = false
            val sender =
                newSender {
                    if (++opens == 1) {
                        File(it).inputStream()
                    } else {
                        CancellingOnSecondRead(File(it).inputStream(), onCancel = { cancel() }, onClose = {
                            closed =
                                true
                        })
                    }
                }
            val state = sender.send(request(file))
            runCurrent()
            accept()

            assertEquals(2, session.sentFrames.count { it.hasFileChunk() })
            assertTrue(session.sentFrames.none { it.hasFileComplete() })
            assertTrue(closed)
            assertEquals(SenderState.Cancelled(TransferReason.TRANSFER_REASON_USER_CANCELLED), state.value)
        }

    private fun cancel() {
        session.emitIncoming(
            envelope {
                channel = Channel.CHANNEL_FILES
                fileCancel =
                    fileCancel {
                        id = ID
                        reason = TransferReason.TRANSFER_REASON_USER_CANCELLED
                    }
            },
        )
    }

    private suspend fun TestScope.startAccepted(file: File): StateFlow<SenderState> {
        val state = newSender { File(it).inputStream() }.send(request(file))
        runCurrent()
        accept()
        return state
    }

    private fun TestScope.accept() {
        session.emitIncoming(
            envelope {
                channel = Channel.CHANNEL_FILES
                fileAccept = fileAccept { id = ID }
            },
        )
        runCurrent()
    }

    private fun TestScope.newSender(reader: SourceFileReader): FileSender {
        val dispatcher = StandardTestDispatcher(testScheduler)
        return FileSender(
            session,
            FilesScheduler(session, dispatcher),
            reader,
            StandardTestDispatcher(testScheduler),
            dispatcher,
        )
    }

    private fun request(file: File) = SendRequest(ID, file.path, "${file.name}.txt", "text/plain")

    private fun fixture(
        name: String,
        bytes: ByteArray,
    ): File = File(dir, name).also { it.writeBytes(bytes) }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

    private class CancellingOnSecondRead(
        private val delegate: InputStream,
        private val onCancel: () -> Unit,
        private val onClose: () -> Unit,
    ) : InputStream() {
        private var reads = 0

        override fun read(): Int = delegate.read()

        override fun read(
            b: ByteArray,
            off: Int,
            len: Int,
        ): Int {
            if (++reads == 2) onCancel()
            return delegate.read(b, off, len)
        }

        override fun close() {
            onClose()
            delegate.close()
        }
    }

    private class FailingAfter(
        private var remaining: Int,
    ) : InputStream() {
        override fun read(): Int = throw IOException("boom")

        override fun read(
            b: ByteArray,
            off: Int,
            len: Int,
        ): Int {
            if (remaining <= 0) throw IOException("boom")
            val n = minOf(len, remaining)
            remaining -= n
            return n
        }
    }

    private companion object {
        const val ABC_SHA256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        const val ID = "t1"
        const val MIB = 1024 * 1024
        const val CHUNK = 262_144L
    }
}
