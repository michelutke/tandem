package dev.tandem.feature.messaging

import android.app.Instrumentation
import android.content.ContentValues
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.Telephony
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.rules.ExternalResource

/**
 * Makes the androidTest APK the default SMS app for the test's duration (the shell uid cannot write
 * the SMS provider; the default SMS holder can) and restores the previous holder afterwards.
 */
class DefaultSmsRoleRule : ExternalResource() {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val packageName = instrumentation.targetContext.packageName
    private var originalHolder = ""

    override fun before() {
        originalHolder = Telephony.Sms.getDefaultSmsPackage(instrumentation.targetContext).orEmpty()
        instrumentation.shell("cmd role add-role-holder --user 0 $SMS_ROLE $packageName")
        if (!instrumentation.awaitHolder(packageName)) {
            instrumentation.shell("settings put secure $LEGACY_SMS_SETTING $packageName")
            check(instrumentation.awaitHolder(packageName)) { "could not become the default SMS app" }
        }
    }

    override fun after() {
        if (originalHolder.isEmpty()) {
            instrumentation.shell("cmd role remove-role-holder --user 0 $SMS_ROLE $packageName")
        } else {
            instrumentation.shell("cmd role add-role-holder --user 0 $SMS_ROLE $originalHolder")
            instrumentation.shell("settings put secure $LEGACY_SMS_SETTING $originalHolder")
        }
    }

    private fun Instrumentation.awaitHolder(expected: String): Boolean {
        repeat(HOLDER_POLL_COUNT) {
            if (Telephony.Sms.getDefaultSmsPackage(targetContext) == expected) return true
            Thread.sleep(HOLDER_POLL_INTERVAL_MS)
        }
        return false
    }

    private companion object {
        const val SMS_ROLE = "android.app.role.SMS"
        const val LEGACY_SMS_SETTING = "sms_default_application"
        const val HOLDER_POLL_COUNT = 50
        const val HOLDER_POLL_INTERVAL_MS = 200L
    }
}

/** Runs a shell command and returns its output once it has finished. */
internal fun Instrumentation.shell(command: String): String =
    ParcelFileDescriptor
        .AutoCloseInputStream(uiAutomation.executeShellCommand(command))
        .use { it.readBytes().decodeToString() }

/** Inserts an inbox row as the default SMS app and returns its uri. */
internal fun Instrumentation.insertInboxSms(
    address: String,
    body: String,
): Uri {
    val values =
        ContentValues().apply {
            put("address", address)
            put("body", body)
            put("read", 0)
        }
    return checkNotNull(targetContext.contentResolver.insert(Uri.parse("content://sms/inbox"), values)) {
        "SMS provider refused the seeded insert"
    }
}
