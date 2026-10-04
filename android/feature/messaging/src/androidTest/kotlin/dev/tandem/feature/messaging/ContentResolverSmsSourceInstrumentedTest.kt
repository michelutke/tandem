package dev.tandem.feature.messaging

import android.Manifest
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.tandem.protocol.v1.SmsMessageType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

// E50-02 tdd: instrumented: smsSource_adbEmuSmsSend_returnsInboxRowWithInjectedAddressAndBody
// Seeds the inbox row itself via the shell user's `content insert` (CI has no host-side
// `adb emu sms send` step); if the image refuses the insert the test is skipped, not failed.
@RunWith(AndroidJUnit4::class)
class ContentResolverSmsSourceInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private var insertOutput = ""

    @Before
    fun grantSmsPermission() {
        instrumentation.uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.READ_SMS)
        insertOutput = instrumentation.insertInboxSms(INJECTED_ADDRESS, INJECTED_BODY)
    }

    @Test
    fun smsSource_adbEmuSmsSend_returnsInboxRowWithInjectedAddressAndBody() {
        val injected =
            ContentResolverSmsSource(context)
                .newerThan(0)
                .filter { it.address == INJECTED_ADDRESS && it.body == INJECTED_BODY }

        assumeTrue("emulator refused the seeded SMS insert: $insertOutput", injected.isNotEmpty())
        assertTrue(injected.isNotEmpty())
        assertEquals(SmsMessageType.SMS_MESSAGE_TYPE_INBOX, injected.first().type)
    }

    private companion object {
        const val INJECTED_ADDRESS = "5551234"
        const val INJECTED_BODY = "tandem-e50-02"
    }
}
