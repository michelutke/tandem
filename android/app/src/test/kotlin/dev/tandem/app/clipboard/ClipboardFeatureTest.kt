package dev.tandem.app.clipboard

import android.app.Application
import android.content.ClipboardManager
import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.app.connection.feature.ClipboardFeature
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.feature.clipboard.ClipboardSender
import dev.tandem.feature.clipboard.LiveClipboardSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.clipboardText
import dev.tandem.protocol.v1.envelope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

// Manual-test regression: the phone's clipboard path end to end on the real composition pieces
// (ClipboardFeature + ClipboardWriter + ClipboardSender over a FakeTandemSession).
@RunWith(AndroidJUnit4::class)
@Config(application = Application::class)
@OptIn(ExperimentalCoroutinesApi::class)
class ClipboardFeatureTest {
    private val clipboardManager: ClipboardManager =
        RuntimeEnvironment.getApplication().getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    private val peer = SpkiFingerprint(ByteArray(32))

    @Test
    fun clipboardFeature_attached_exposesSessionToSendEntryPointsAndClearsItOnEnd() =
        runTest(UnconfinedTestDispatcher()) {
            val session = FakeTandemSession()
            val job = launch { ClipboardFeature(ClipboardWriter(clipboardManager)).run(session, peer, null) }

            assertSame(session, LiveClipboardSession.current)
            job.cancel()
            job.join()
            assertNull(LiveClipboardSession.current)
        }

    @Test
    fun clipboardFeature_macSendsClipboardText_writesSystemClipboardAndConfirms() =
        runTest(UnconfinedTestDispatcher()) {
            val session = FakeTandemSession()
            var confirmations = 0
            val job =
                launch {
                    ClipboardFeature(ClipboardWriter(clipboardManager) { confirmations++ }).run(session, peer, null)
                }

            session.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_CLIPBOARD
                    clipboardText = clipboardText { text = "from the mac" }
                },
            )

            assertEquals(
                "from the mac",
                clipboardManager.primaryClip
                    ?.getItemAt(0)
                    ?.text
                    ?.toString(),
            )
            assertEquals(1, confirmations)
            job.cancel()
        }

    @Test
    fun clipboardSender_throughLiveSession_sendsClipboardTextOnClipboardChannel() =
        runTest(UnconfinedTestDispatcher()) {
            val session = FakeTandemSession()
            val job = launch { ClipboardFeature(ClipboardWriter(clipboardManager)).run(session, peer, null) }

            ClipboardSender.send("to the mac", checkNotNull(LiveClipboardSession.current))

            val frame = session.sentFrames.single()
            assertEquals(Channel.CHANNEL_CLIPBOARD, frame.channel)
            assertEquals("to the mac", frame.clipboardText.text)
            job.cancel()
        }
}
