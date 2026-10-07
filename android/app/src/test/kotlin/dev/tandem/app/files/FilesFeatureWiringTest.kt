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
import dev.tandem.feature.files.TransferPrompter
import dev.tandem.protocol.v1.Channel
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

    private fun TestScope.startFeature(): Job {
        val context: Context = RuntimeEnvironment.getApplication()
        val feature =
            FilesFeature(
                store = FileTransferStore(temporaryFolder.newFolder(), Clock.systemUTC()),
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
                clock = Clock.systemUTC(),
                ioDispatcher = StandardTestDispatcher(testScheduler),
                serialDispatcher = { StandardTestDispatcher(testScheduler) },
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
