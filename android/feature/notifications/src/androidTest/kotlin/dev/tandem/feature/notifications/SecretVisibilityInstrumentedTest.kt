package dev.tandem.feature.notifications

import android.content.Context
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
    private val listenerComponent = "${context.packageName}/${CapturingListenerService::class.java.name}"

    @Before
    fun grantAccess() {
        installCompanion()
        val grant = shellOutput("pm grant $COMPANION_PACKAGE android.permission.POST_NOTIFICATIONS")
        assertTrue("POST_NOTIFICATIONS grant failed: $grant", grant.isBlank())
        shellOutput("cmd notification allow_listener $listenerComponent $USER_ID")
        awaitListenerConnected()
        CapturingListenerService.captured.clear()
    }

    @After
    fun cancelPost() {
        shellOutput(companionCommand(KIND_CANCEL))
        shellOutput("cmd notification disallow_listener $listenerComponent $USER_ID")
    }

    @Test
    fun secretVisibility_companionSecretKind_capturedPayloadHasEmptyText() {
        val post = companionCommand(KIND_SECRET, "--es text $SECRET_TEXT")

        val posted = awaitCaptured(post)

        assertEquals(CapturingListenerService.COMPANION_APP_NAME, posted.title)
        assertEquals("", posted.text)
        assertTrue(posted.messagingStyleSendersList.isEmpty())
        assertEquals(Visibility.VISIBILITY_SECRET, posted.visibility)
    }

    private fun companionCommand(
        kind: String,
        extras: String = "",
    ): String =
        "am broadcast --user $USER_ID --receiver-foreground -n $COMPANION_RECEIVER " +
            "-a dev.tandem.companion.POST --es kind $kind --es key $POST_KEY $extras"

    private fun awaitListenerConnected() {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(TIMEOUT_SECONDS)
        while (!CapturingListenerService.connected) {
            check(System.nanoTime() < deadline) { "notification listener not connected within ${TIMEOUT_SECONDS}s" }
            Thread.sleep(POLL_INTERVAL_MS)
        }
    }

    // The first broadcast can land while the just-installed companion is still settling and be
    // dropped, so the (idempotent, same-key) post is re-sent until the listener sees it.
    private fun awaitCaptured(post: String): NotificationPosted {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(TIMEOUT_SECONDS)
        var nextPost = 0L
        while (System.nanoTime() < deadline) {
            CapturingListenerService.captured.firstOrNull()?.let { return it }
            if (System.nanoTime() >= nextPost) {
                shellOutput(post)
                nextPost = System.nanoTime() + TimeUnit.SECONDS.toNanos(REPOST_INTERVAL_SECONDS)
            }
            Thread.sleep(POLL_INTERVAL_MS)
        }
        error("no companion notification captured within ${TIMEOUT_SECONDS}s")
    }

    private fun installCompanion() {
        val apk = File(context.externalCacheDir, COMPANION_APK_ASSET)
        context.assets.open(COMPANION_APK_ASSET).use { input -> apk.outputStream().use(input::copyTo) }
        apk.setReadable(true, false)
        // API 29's installer can't read app-scoped external storage; stage the APK where it can.
        val staged = "/data/local/tmp/$COMPANION_APK_ASSET"
        shellOutput("cp ${apk.absolutePath} $staged")
        val output = shellOutput("pm install -r -g $staged")
        assertTrue("companion install failed: $output", output.contains("Success"))
    }

    private fun shellOutput(command: String): String =
        ParcelFileDescriptor
            .AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command))
            .use { it.readBytes().decodeToString() }

    private companion object {
        const val COMPANION_PACKAGE = CapturingListenerService.COMPANION_PACKAGE
        const val COMPANION_RECEIVER = "$COMPANION_PACKAGE/.CompanionReceiver"
        const val USER_ID = 0
        const val COMPANION_APK_ASSET = "companion.apk"
        const val KIND_SECRET = "secret"
        const val KIND_CANCEL = "cancel"
        const val POST_KEY = "secret-visibility-test"
        const val SECRET_TEXT = "secretbody"
        const val POLL_INTERVAL_MS = 50L
        const val TIMEOUT_SECONDS = 60L
        const val REPOST_INTERVAL_SECONDS = 10L
    }
}
