package dev.tandem.feature.mirror

import android.Manifest
import android.content.Intent
import android.media.projection.MediaProjectionManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.RequiresDevice
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.mirrorRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant

/** E61-16 manual tdd: `mirrorPrompt_tapNotificationOnEmulator_consentDialogShown` (E00-21). */
@RunWith(AndroidJUnit4::class)
class MirrorPromptInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)

    @Test
    @RequiresDevice
    fun mirrorPrompt_tapNotificationOnEmulator_consentDialogShown() {
        val context = instrumentation.targetContext
        instrumentation.uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.POST_NOTIFICATIONS)
        val session = FakeTandemSession().also { it.emitState(ConnectionState.Ready(Instant.EPOCH)) }
        val launcher =
            MediaProjectionConsentLauncher(context.getSystemService(MediaProjectionManager::class.java)) { intent ->
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        val controller =
            MirrorPromptController(
                session = session,
                presenter = NotificationMirrorPromptPresenter(context, MirrorStartTrampolineActivity::class.java),
                starter = MirrorSessionStarter(launcher),
                peerName = PEER_NAME,
                scope = CoroutineScope(Dispatchers.Default),
                onUserStart = {},
            )
        controller.start()
        MirrorPromptActionDispatcher.controller = controller
        session.emitIncoming(
            envelope {
                channel = Channel.CHANNEL_CONTROL
                mirrorRequest = mirrorRequest { }
            },
        )

        device.openNotification()
        device.wait(Until.hasObject(By.text("Mirror to $PEER_NAME?")), UI_TIMEOUT_MILLIS)
        device.findObject(By.text("Mirror to $PEER_NAME?")).click()

        assertNotNull(device.wait(Until.findObject(By.text("Start now")), UI_TIMEOUT_MILLIS))
    }

    private companion object {
        const val PEER_NAME = "Test Mac"
        const val UI_TIMEOUT_MILLIS = 5_000L
    }
}
