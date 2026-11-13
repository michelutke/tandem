package dev.tandem.app.files

import android.app.Application
import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.protobuf.ByteString
import dev.tandem.app.connection.feature.FilesFeature
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.feature.files.AcceptSettings
import dev.tandem.feature.files.FileTransferStore
import dev.tandem.feature.files.LiveFileSession
import dev.tandem.feature.files.MediaPermissionChecker
import dev.tandem.feature.files.SendFeedback
import dev.tandem.feature.files.SendRequest
import dev.tandem.feature.files.TransferActionDispatcher
import dev.tandem.feature.files.TransferProgressNotifier
import dev.tandem.feature.files.TransferPrompter
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.TransferReason
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.fileAccept
import dev.tandem.protocol.v1.fileOffer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.ByteArrayInputStream
import java.security.MessageDigest
import java.time.Clock

// Manual-test regression: the phone's file paths end to end on the real FilesFeature composition
// over a FakeTandemSession. Mac -> phone needs the notification Accept tap routed to the live
// AcceptFlow; phone -> Mac needs the share-sheet / picker starter bound to the live FileSender.
@RunWith(AndroidJUnit4::class)
@Config(application = Application::class)
@OptIn(ExperimentalCoroutinesApi::class)
class FilesFeatureWiringTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private val session = FakeTandemSession()
    private val peer = SpkiFingerprint(ByteArray(32))
    private val prompted = mutableListOf<String>()

    @Test
    fun filesFeature_macOffersFile_acceptTapRoutedToLiveAcceptFlowSendsFileAccept() =
        runTest {
            val job = startFeature()

            session.emitIncoming(offerFromMac())
            runCurrent()
            assertEquals(listOf(OFFER_ID), prompted)
            checkNotNull(TransferActionDispatcher.acceptFlow).accept(OFFER_ID)
            runCurrent()

            assertEquals(
                OFFER_ID,
                session.sentFrames
                    .single { it.hasFileAccept() }
                    .fileAccept.id,
            )
            job.cancel()
        }

    @Test
    fun filesFeature_attached_phoneSendReachesMacAndReportsFeedback() =
        runTest {
            val job = startFeature()
            val feedback = mutableListOf<SendFeedback>()

            LiveFileSession.starter { feedback += it }.start(sendRequest())
            runCurrent()
            assertEquals(
                SEND_ID,
                session.sentFrames
                    .single { it.hasFileOffer() }
                    .fileOffer.id,
            )
            session.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_FILES
                    fileAccept = fileAccept { id = SEND_ID }
                },
            )
            runCurrent()

            assertTrue(session.sentFrames.any { it.hasFileComplete() })
            assertEquals(listOf(SendFeedback.STARTED, SendFeedback.SENT), feedback)
            job.cancel()
        }

    @Test
    fun filesFeature_attached_sendCompletes_reportsFinishedRequest() =
        runTest {
            val job = startFeature()
            val finished = mutableListOf<SendRequest>()

            LiveFileSession.starter(onFinished = { finished += it }) {}.start(sendRequest())
            runCurrent()
            assertTrue(finished.isEmpty())
            session.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_FILES
                    fileAccept = fileAccept { id = SEND_ID }
                },
            )
            runCurrent()

            assertEquals(listOf(SEND_ID), finished.map { it.id })
            job.cancel()
        }

    @Test
    fun liveFileSession_sessionEndsMidTransfer_reportsFailedAndFinishes() =
        runTest {
            val job = startFeature()
            val feedback = mutableListOf<SendFeedback>()
            val finished = mutableListOf<SendRequest>()
            LiveFileSession.starter(onFinished = { finished += it }) { feedback += it }.start(sendRequest())
            runCurrent()

            job.cancel()
            runCurrent()

            assertEquals(listOf(SendFeedback.STARTED, SendFeedback.FAILED), feedback)
            assertEquals(listOf(SEND_ID), finished.map { it.id })
        }

    @Test
    fun filesFeature_notAttached_sendReportsFinishedRequestAtOnce() {
        val finished = mutableListOf<SendRequest>()

        LiveFileSession.starter(onFinished = { finished += it }) {}.start(sendRequest())

        assertEquals(listOf(SEND_ID), finished.map { it.id })
    }

    @Test
    fun filesFeature_sessionEnds_unbindsSendAndAcceptEntryPoints() =
        runTest {
            val job = startFeature()
            job.cancel()
            runCurrent()
            val feedback = mutableListOf<SendFeedback>()

            LiveFileSession.starter { feedback += it }.start(sendRequest())

            assertEquals(listOf(SendFeedback.NOT_CONNECTED), feedback)
            assertNull(TransferActionDispatcher.acceptFlow)
        }

    @Test
    fun filesFeature_cancelActionTapped_receiverSendsFileCancelUserCancelledAndDeletesPart() =
        runTest {
            val store = FileTransferStore(temporaryFolder.newFolder(), Clock.systemUTC())
            val job = startFeature(store)
            session.emitIncoming(offerFromMac())
            runCurrent()
            checkNotNull(TransferActionDispatcher.acceptFlow).accept(OFFER_ID)
            runCurrent()
            assertEquals(listOf(OFFER_ID), store.ids())

            checkNotNull(TransferActionDispatcher.cancelTransfer).invoke(OFFER_ID)
            runCurrent()

            assertEquals(
                TransferReason.TRANSFER_REASON_USER_CANCELLED,
                session.sentFrames
                    .single { it.hasFileCancel() }
                    .fileCancel.reason,
            )
            assertTrue(store.ids().isEmpty())
            job.cancel()
        }

    @Test
    fun filesFeature_sessionStarts_sweepsExpiredPartFiles() =
        runTest {
            val store = FileTransferStore(temporaryFolder.newFolder(), Clock.systemUTC())
            store.create("stale")
            store.writeMeta("stale", peer.bytes + staleOffer("stale").toByteArray())
            val staleClock = Clock.fixed(Clock.systemUTC().instant().plusSeconds(25 * 3600), java.time.ZoneOffset.UTC)

            val job = startFeature(store, staleClock)

            assertTrue(store.ids().isEmpty())
            job.cancel()
        }

    @Test
    fun filesFeature_reconnectWithRetainedPart_sendsFileResumeRequest() =
        runTest {
            val store = FileTransferStore(temporaryFolder.newFolder(), Clock.systemUTC())
            store.create("part-1")
            store.append("part-1", CONTENT.copyOf(2))
            store.writeMeta("part-1", peer.bytes + staleOffer("part-1").toByteArray())

            val job = startFeature(store)

            assertEquals(
                "part-1",
                session.sentFrames
                    .single { it.hasFileResumeRequest() }
                    .fileResumeRequest.id,
            )
            job.cancel()
        }

    private fun staleOffer(offerId: String) =
        fileOffer {
            id = offerId
            name = "from-mac.txt"
            size = CONTENT.size.toLong()
            mime = "text/plain"
            sha256 = ByteString.copyFrom(MessageDigest.getInstance("SHA-256").digest(CONTENT))
        }

    private fun TestScope.startFeature(
        store: FileTransferStore = FileTransferStore(temporaryFolder.newFolder(), Clock.systemUTC()),
        clock: Clock = Clock.systemUTC(),
    ): Job {
        val context: Context = RuntimeEnvironment.getApplication()
        val feature =
            FilesFeature(
                store = store,
                publisher = { _, _, _ -> "content://downloads/1" },
                notifier = { _, _, _ -> },
                prompter =
                    object : TransferPrompter {
                        override fun post(
                            offerId: String,
                            displayName: String,
                            sizeBytes: Long,
                        ) {
                            prompted += offerId
                        }

                        override fun cancel(offerId: String) = Unit
                    },
                freeSpace = { Long.MAX_VALUE / 2 },
                reader = { ByteArrayInputStream(CONTENT) },
                mediaSource = { _, _ -> emptyList() },
                thumbnailLoader = { _, _ -> error("unused") },
                permissionChecker = MediaPermissionChecker(context),
                acceptSettings = { AcceptSettings() },
                clock = clock,
                ioDispatcher = StandardTestDispatcher(testScheduler),
                serialDispatcher = { StandardTestDispatcher(testScheduler) },
                progressNotifier = TransferProgressNotifier(context),
            )
        val job = launch { feature.run(session, peer, null) }
        runCurrent()
        return job
    }

    private fun sendRequest() = SendRequest(SEND_ID, "content://x/1", "a.txt", "text/plain")

    private fun offerFromMac() =
        envelope {
            channel = Channel.CHANNEL_FILES
            fileOffer =
                fileOffer {
                    id = OFFER_ID
                    name = "from-mac.txt"
                    size = CONTENT.size.toLong()
                    mime = "text/plain"
                    sha256 = ByteString.copyFrom(MessageDigest.getInstance("SHA-256").digest(CONTENT))
                }
        }

    private companion object {
        const val OFFER_ID = "offer-1"
        const val SEND_ID = "send-1"
        val CONTENT = "hello".toByteArray()
    }
}
