package dev.tandem.feature.files

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.testing.TestClock
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.Envelope
import dev.tandem.protocol.v1.EnvelopeKt
import dev.tandem.protocol.v1.TransferReason
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.fileAccept
import dev.tandem.protocol.v1.fileResumeRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.time.Instant

// E40-09 tdd (docs/planning/backlog/phase-4.yaml): a real FileSender and FileReceiver joined by
// frame forwarding between FakeTandemSessions, as in FileResumeTest; per-direction capture is
// each session's sentFrames.
@OptIn(ExperimentalCoroutinesApi::class)
class FileCancelTest {
    @TempDir
    lateinit var dir: File

    private val publisher = RecordingPublisher()
    private val retained = RetainedSends()

    @Test
    fun androidCancel_senderInitiated_noChunkAfterCancelAndReceiverPartDeleted() =
        runTest {
            val store = FileTransferStore(File(dir, "rx"), TestClock(testScheduler, START))
            val link = link(store, source(8 * CHUNK), chunkLimit = 2)
            val state = link.sendAndAccept()
            link.deliverSenderFrames()
            assertEquals(1, store.ids().size)

            link.sender.cancelTransfer(ID)
            runCurrent()
            link.senderSession.releaseChunks()
            runCurrent()
            link.deliverSenderFrames()

            val frames = link.senderSession.sentFrames
            val cancelIndex = frames.indexOfFirst { it.hasFileCancel() }
            assertEquals(TransferReason.TRANSFER_REASON_USER_CANCELLED, frames[cancelIndex].fileCancel.reason)
            assertTrue(frames.drop(cancelIndex).none { it.hasFileChunk() })
            assertTrue(store.ids().isEmpty())
            assertTrue(dir.walk().none { it.name.endsWith(".part") || it.name.endsWith(".meta") })
            assertTrue(publisher.published.isEmpty())
            assertEquals(SenderState.Cancelled(TransferReason.TRANSFER_REASON_USER_CANCELLED), state.value)
        }

    @Test
    fun androidCancel_receiverInitiated_senderStopsWithinCreditWindow() =
        runTest {
            val store = FileTransferStore(File(dir, "rx"), TestClock(testScheduler, START))
            val link = link(store, source(40 * CHUNK), chunkLimit = 3)
            val state = link.sendAndAccept()
            link.deliverSenderFrames()

            link.receiver.cancelTransfer(ID)
            runCurrent()
            link.receiverSession.sentFrames
                .filter { it.hasFileCancel() }
                .forEach { link.senderSession.emitIncoming(it) }
            runCurrent()
            link.senderSession.releaseChunks()
            runCurrent()

            val cancel =
                link.receiverSession.sentFrames
                    .single { it.hasFileCancel() }
                    .fileCancel
            assertEquals(TransferReason.TRANSFER_REASON_USER_CANCELLED, cancel.reason)
            val chunks = link.senderSession.sentFrames.count { it.hasFileChunk() }
            assertTrue(chunks <= 3 + 1, "sent $chunks")
            assertEquals(SenderState.Cancelled(TransferReason.TRANSFER_REASON_USER_CANCELLED), state.value)
            assertTrue(store.ids().isEmpty())
        }

    @Test
    fun androidCancel_resumeForCancelledId_unknownTransferCancel() =
        runTest {
            val store = FileTransferStore(File(dir, "rx"), TestClock(testScheduler, START))
            val link = link(store, source(4 * CHUNK), chunkLimit = 1)
            link.sendAndAccept()
            link.sender.cancelTransfer(ID)
            runCurrent()
            link.senderSession.releaseChunks()
            runCurrent()
            val before = link.senderSession.sentFrames.size

            link.senderSession.emitIncoming(resumeRequest())
            runCurrent()

            val answer =
                link.senderSession.sentFrames
                    .drop(before)
                    .single()
            assertEquals(ID, answer.fileReject.id)
            assertEquals(TransferReason.TRANSFER_REASON_UNKNOWN_TRANSFER, answer.fileReject.reason)
        }

    private fun TestScope.link(
        store: TransferStore,
        source: File,
        chunkLimit: Int,
    ): Link {
        val senderSession = GatedSession(chunkLimit)
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
                ReceivedFileNotifier { _, _, _ -> },
                SpkiFingerprint(ByteArray(32) { 1 }),
                TestClock(testScheduler, START),
                StandardTestDispatcher(testScheduler),
                dispatcher,
            )
        return Link(this, source, sender, receiver, senderSession, receiverSession)
    }

    private class Link(
        private val scope: TestScope,
        private val source: File,
        val sender: FileSender,
        val receiver: FileReceiver,
        val senderSession: GatedSession,
        val receiverSession: FakeTandemSession,
    ) {
        private var delivered = 0

        fun sendAndAccept(): StateFlow<SenderState> {
            val state = sender.send(SendRequest(ID, source.path, "file.bin", "application/octet-stream"))
            scope.runCurrent()
            receiver.expect(senderSession.sentFrames.single().fileOffer)
            scope.runCurrent()
            senderSession.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_FILES
                    fileAccept = fileAccept { id = ID }
                },
            )
            scope.runCurrent()
            delivered = 1
            return state
        }

        fun deliverSenderFrames() {
            val frames = senderSession.sentFrames
            frames.drop(delivered).forEach { receiverSession.emitIncoming(it) }
            delivered = frames.size
            scope.runCurrent()
        }
    }

    private fun source(size: Int): File =
        File(dir, "source.bin").also { file -> file.writeBytes(ByteArray(size) { (it % 251).toByte() }) }

    private fun resumeRequest(): Envelope =
        envelope {
            channel = Channel.CHANNEL_FILES
            fileResumeRequest =
                fileResumeRequest {
                    id = ID
                    fromOffset = 0
                }
        }

    /** Suspends every chunk send beyond [limit] until [releaseChunks], standing in for exhausted credit. */
    private class GatedSession(
        private val limit: Int,
        private val fake: FakeTandemSession = FakeTandemSession(),
    ) : TandemSession by fake {
        private val gate = CompletableDeferred<Unit>()
        private var chunksSent = 0

        val sentFrames: List<Envelope> get() = fake.sentFrames

        fun emitIncoming(envelope: Envelope) = fake.emitIncoming(envelope)

        fun releaseChunks() {
            gate.complete(Unit)
        }

        override suspend fun send(
            channel: Channel,
            payload: EnvelopeKt.Dsl.() -> Unit,
        ) {
            val isChunk = envelope { payload() }.hasFileChunk()
            if (isChunk && ++chunksSent > limit) gate.await()
            fake.send(channel, payload)
        }
    }

    private class RecordingPublisher : DownloadsPublisher {
        val published = mutableListOf<ByteArray>()

        @Throws(IOException::class)
        override fun publish(
            name: String,
            mime: String,
            content: InputStream,
        ): String {
            published += content.readBytes()
            return "content://downloads/${published.size}"
        }
    }

    private companion object {
        const val ID = "t1"
        const val CHUNK = 262_144
        val START: Instant = Instant.ofEpochSecond(1_700_000_000)
    }
}
