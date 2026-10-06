package dev.tandem.feature.input

import android.app.UiAutomation
import android.content.ComponentName
import android.content.Intent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.RequiresDevice
import androidx.test.platform.app.InstrumentationRegistry
import dev.tandem.protocol.v1.GlobalActionKind
import dev.tandem.protocol.v1.globalAction
import dev.tandem.protocol.v1.setText
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.FileInputStream

// E62-05 tdd:
//   instrumented: setText_focusedEditTextOnEmulator_contentReplaced
//   manual: globalActionHome_onEmulator_launcherInForeground
//
// Enables this test APK's CapturingAccessibilityService via `settings put secure` (E00-21), then
// drives the real ServiceAccessibilityActions through InputActionHandler.
@RunWith(AndroidJUnit4::class)
class AccessibilityInputInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.context
    private val serviceComponent = "${context.packageName}/${CapturingAccessibilityService::class.java.name}"

    @Before
    fun enableService() {
        shell("settings put secure enabled_accessibility_services $serviceComponent")
        shell("settings put secure accessibility_enabled 1")
        awaitNotNull { CapturingAccessibilityService.instance }
    }

    @After
    fun disableService() {
        shell("settings put secure enabled_accessibility_services \"\"")
        shell("settings put secure accessibility_enabled 0")
    }

    @Test
    fun setText_focusedEditTextOnEmulator_contentReplaced() {
        val intent =
            Intent()
                .setComponent(ComponentName(context.packageName, EditTextTestActivity::class.java.name))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ActivityScenario.launch<EditTextTestActivity>(intent).use { scenario ->
            val handler = handler()

            val result =
                awaitNotNull {
                    handler.handle(setText { text = REPLACEMENT }).takeIf {
                        it ==
                            InputResult.Performed
                    }
                }

            assertEquals(InputResult.Performed, result)
            var content = ""
            scenario.onActivity { content = it.editText.text.toString() }
            assertEquals(REPLACEMENT, content)
        }
    }

    @Test
    @RequiresDevice
    fun globalActionHome_onEmulator_launcherInForeground() {
        val result = handler().handle(globalAction { action = GlobalActionKind.GLOBAL_ACTION_KIND_HOME })

        assertEquals(InputResult.Performed, result)
        val launcher =
            checkNotNull(Regex("""\{([^/]+)/""").find(shell("cmd shortcut get-default-launcher"))?.groupValues?.get(1))
        awaitNotNull {
            launcher.takeIf {
                shell("dumpsys activity activities")
                    .lineSequence()
                    .any { line -> line.contains(TOP_RESUMED_MARKER) && line.contains(" $it/") }
            }
        }
    }

    private fun handler() =
        InputActionHandler(ServiceAccessibilityActions(checkNotNull(CapturingAccessibilityService.instance)))

    private fun shell(command: String): String =
        FileInputStream(
            instrumentation
                .getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)
                .executeShellCommand(command)
                .fileDescriptor,
        ).use {
            it.readBytes().decodeToString()
        }

    private fun <T : Any> awaitNotNull(block: () -> T?): T {
        val deadline = System.currentTimeMillis() + TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            block()?.let { return it }
            Thread.sleep(POLL_MS)
        }
        throw AssertionError("condition not met within ${TIMEOUT_MS}ms")
    }

    private companion object {
        const val REPLACEMENT = "after"
        const val TOP_RESUMED_MARKER = "topResumedActivity="
        const val TIMEOUT_MS = 10_000L
        const val POLL_MS = 200L
    }
}
