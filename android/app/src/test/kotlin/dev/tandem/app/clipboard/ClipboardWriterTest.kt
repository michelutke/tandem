package dev.tandem.app.clipboard

import android.app.Application
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.clipboardText
import dev.tandem.protocol.v1.envelope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * [ClipboardWriter] tests (E31-05). Runs under Robolectric (E00-20) because
 * `android.content.ClipboardManager` is an unavoidable framework type; `@Config(sdk = ...)`
 * pins each test to the Android version its assertion is about, per
 * `clipboardWriter_receivedText_primaryClipEqualsText`'s `[29, 33]` -- Robolectric runs that test
 * once per listed SDK -- versus the API-33-only and API-29-only tests below it.
 *
 * Class-level `application = Application::class` swaps out `TandemApplication` (this module's
 * real, manifest-declared `@HiltAndroidApp`): its `onCreate` launches an unscoped
 * `Dispatchers.Default` coroutine that opens the real `TrustStore` Room database
 * (`ServiceStarter.start`, E20-02), which has nothing to do with clipboard writing and, left in
 * place, races Robolectric's per-test sandbox teardown across this class's several `@Config(sdk =
 * ...)` boots (surfaced as flaky native-SQLite `UnsatisfiedLinkError`/`FileSystemAlreadyExistsException`
 * failures). A plain `Application`'s `onCreate` is a no-op, and method-level `@Config(sdk = ...)`
 * below merges with this class-level `application` override rather than replacing it.
 */
@RunWith(AndroidJUnit4::class)
@Config(application = Application::class)
@OptIn(ExperimentalCoroutinesApi::class)
class ClipboardWriterTest {
    private fun clipboardManager(): ClipboardManager =
        RuntimeEnvironment.getApplication().getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    private fun driveIncoming(
        writer: ClipboardWriter,
        text: String,
        sensitive: Boolean,
    ) = runTest {
        val session = FakeTandemSession()
        val job = launch { writer.start(session) }

        session.emitIncoming(
            envelope {
                channel = Channel.CHANNEL_CLIPBOARD
                seq = 1
                clipboardText =
                    clipboardText {
                        this.text = text
                        this.sensitive = sensitive
                        originTag = "macos"
                    }
            },
        )
        advanceUntilIdle()
        job.cancel()
    }

    @Test
    @Config(sdk = [29, 33])
    fun clipboardWriter_receivedText_primaryClipEqualsText() {
        val writer = ClipboardWriter(clipboardManager())

        driveIncoming(writer, text = "hello tandem", sensitive = false)

        val readBack =
            clipboardManager()
                .primaryClip
                ?.getItemAt(0)
                ?.text
                .toString()
        assertEquals("hello tandem", readBack)
    }

    @Test
    @Config(sdk = [33])
    fun clipboardWriter_sensitiveOnApi33_extraIsSensitiveTrue() {
        val writer = ClipboardWriter(clipboardManager())

        driveIncoming(writer, text = "secret", sensitive = true)

        val extras = clipboardManager().primaryClip?.description?.extras
        assertTrue(extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE) == true)
    }

    @Test
    @Config(sdk = [33])
    fun clipboardWriter_notSensitiveOnApi33_extraIsSensitiveAbsent() {
        val writer = ClipboardWriter(clipboardManager())

        driveIncoming(writer, text = "not secret", sensitive = false)

        val extras = clipboardManager().primaryClip?.description?.extras
        assertFalse(extras?.containsKey(ClipDescription.EXTRA_IS_SENSITIVE) == true)
    }

    @Test
    @Config(sdk = [29])
    fun clipboardWriter_sensitiveOnApi29_writtenWithoutExtra() {
        val writer = ClipboardWriter(clipboardManager())

        driveIncoming(writer, text = "secret", sensitive = true)

        val clip = clipboardManager().primaryClip
        assertEquals("secret", clip?.getItemAt(0)?.text.toString())
        assertNull(clip?.description?.extras)
    }
}
