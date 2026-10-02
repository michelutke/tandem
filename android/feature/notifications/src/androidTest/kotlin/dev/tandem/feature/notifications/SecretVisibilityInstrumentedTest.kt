package dev.tandem.feature.notifications

import android.content.Context
import android.content.Intent
import android.os.ParcelFileDescriptor
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.tandem.protocol.v1.NotificationPosted
import dev.tandem.protocol.v1.Visibility
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.TimeUnit

// E30-11 tdd:
//   instrumented: secretVisibility_companionSecretKind_capturedPayloadHasEmptyText
//
// Needs the companion app (E00-22, `dev.tandem.companion`) installed alongside the test APK; the
// CI managed-device workflow installs it before instrumented tests run. Notification access is
// granted to this test APK's CapturingListenerService via `cmd notification allow_listener`.
@RunWith(AndroidJUnit4::class)
class SecretVisibilityInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.context

    @Before
    fun grantAccess() {
        installCompanion()
        shell("pm grant $COMPANION_PACKAGE android.permission.POST_NOTIFICATIONS")
        shell("cmd notification allow_listener ${context.packageName}/${CapturingListenerService::class.java.name}")
        CapturingListenerService.captured.clear()
    }

    @After
    fun cancelPost() {
        context.sendBroadcast(companionCommand(KIND_CANCEL))
        shell("cmd notification disallow_listener ${context.packageName}/${CapturingListenerService::class.java.name}")
    }

    @Test
    fun secretVisibility_companionSecretKind_capturedPayloadHasEmptyText() {
        context.sendBroadcast(companionCommand(KIND_SECRET).putExtra("text", SECRET_TEXT))

        val posted = awaitCaptured()

        assertEquals(CapturingListenerService.COMPANION_APP_NAME, posted.title)
        assertEquals("", posted.text)
        assertTrue(posted.messagingStyleSendersList.isEmpty())
        assertEquals(Visibility.VISIBILITY_SECRET, posted.visibility)
    }

    private fun companionCommand(kind: String): Intent =
        Intent("dev.tandem.companion.POST")
            .setPackage(COMPANION_PACKAGE)
            .addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
            .putExtra("kind", kind)
            .putExtra("key", POST_KEY)

    private fun awaitCaptured(): NotificationPosted {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(TIMEOUT_SECONDS)
        while (System.nanoTime() < deadline) {
            CapturingListenerService.captured.firstOrNull()?.let { return it }
            Thread.sleep(POLL_INTERVAL_MS)
        }
        error("no companion notification captured within ${TIMEOUT_SECONDS}s")
    }

    private fun installCompanion() {
        val apk = File(context.externalCacheDir, COMPANION_APK_ASSET)
        context.assets.open(COMPANION_APK_ASSET).use { input -> apk.outputStream().use(input::copyTo) }
        apk.setReadable(true, false)
        val output = shellOutput("pm install -r -g ${apk.absolutePath}")
        assertTrue("companion install failed: $output", output.contains("Success"))
    }

    private fun shellOutput(command: String): String =
        ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command))
            .use { it.readBytes().decodeToString() }

    private fun shell(command: String) {
        instrumentation.uiAutomation.executeShellCommand(command).close()
    }

    private companion object {
        const val COMPANION_PACKAGE = CapturingListenerService.COMPANION_PACKAGE
        const val COMPANION_APK_ASSET = "companion.apk"
        const val KIND_SECRET = "secret"
        const val KIND_CANCEL = "cancel"
        const val POST_KEY = "secret-visibility-test"
        const val SECRET_TEXT = "secret body"
        const val POLL_INTERVAL_MS = 50L
        const val TIMEOUT_SECONDS = 60L
    }
}
