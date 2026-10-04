package dev.tandem.feature.messaging

import android.Manifest
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.yield
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// E50-03 tdd: instrumented: smsObserver_adbEmuSmsSend_pushRecordedWithin1s
// Seeds the inbox row as the default SMS app (CI has no host-side `adb emu sms send` step).
@RunWith(AndroidJUnit4::class)
class SmsObserverInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @get:Rule
    val defaultSmsRole = DefaultSmsRoleRule()

    @Before
    fun grantSmsPermission() {
        instrumentation.uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.READ_SMS)
    }

    @Test
    fun smsObserver_adbEmuSmsSend_pushRecordedWithin1s() =
        runBlocking {
            val source = ContentResolverSmsSource(context)
            val change = async(start = CoroutineStart.UNDISPATCHED) { source.changes().first() }
            yield()

            instrumentation.insertInboxSms(INJECTED_ADDRESS, INJECTED_BODY)
            val observed = withTimeoutOrNull(OBSERVE_TIMEOUT_MS) { change.await() }

            assertNotNull("no change callback within ${OBSERVE_TIMEOUT_MS}ms", observed)
        }

    private companion object {
        const val INJECTED_ADDRESS = "5551235"
        const val INJECTED_BODY = "tandem-e50-03"
        const val OBSERVE_TIMEOUT_MS = 1_000L
    }
}
