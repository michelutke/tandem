package dev.tandem.app

import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.app.connection.PairingAddressStore
import dev.tandem.app.home.HomeRingState
import dev.tandem.app.onboarding.FakePermissionChecker
import dev.tandem.app.onboarding.OnboardingViewModel
import dev.tandem.app.onboarding.RecordingPermissionRequester
import dev.tandem.app.service.FakePairedPeerRepository
import dev.tandem.app.service.ServiceStarter
import dev.tandem.app.shell.AppShellDependencies
import dev.tandem.app.shell.NoOpPairingStarter
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.feature.clipboard.ClipboardClip
import dev.tandem.feature.clipboard.ClipboardReader
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import java.io.File

// E31-07 tdd:
//   unit: foregroundCapture_windowFocusGainedWithTextClip_sendsClipboardText
//   unit: foregroundCapture_sendClipboardButtonTapped_sendsClipboardText
//   unit: foregroundCapture_noWindowFocus_clipboardReaderNeverCalled
//   unit: foregroundCapture_sensitiveClipOnWindowFocus_notSent
//   unit: foregroundCapture_sensitiveClipViaButton_sentWithSensitiveFlag
//
// Runs on Robolectric (E00-20); see ShareTargetActivityTest's header (`:feature:clipboard`) for
// the seam/dispatcher convention this test shares with it. sessionProvider/dispatcher/
// clipboardReaderProvider are set on the built-but-not-yet-created instance, then
// onWindowFocusChanged/onSendClipboardButtonTapped are invoked directly rather than through a real
// window-focus event or a Compose click, since only the capture logic those seams gate is in
// scope here.
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class MainActivityTest {
    @Test
    fun foregroundCapture_windowFocusGainedWithTextClip_sendsClipboardText() {
        val session = FakeTandemSession()
        val reader = RecordingClipboardReader(ClipboardClip("hello mac", sensitive = false))
        val activity = buildAndCreate(session, reader)

        activity.onWindowFocusChanged(true)

        val sent = session.sentFrames.single().clipboardText
        assertEquals("android", sent.originTag)
        assertEquals("hello mac", sent.text)
        assertEquals(false, sent.sensitive)
    }

    @Test
    fun foregroundCapture_sendClipboardButtonTapped_sendsClipboardText() {
        val session = FakeTandemSession()
        val reader = RecordingClipboardReader(ClipboardClip("hello mac", sensitive = false))
        val activity = buildAndCreate(session, reader)

        activity.onSendClipboardButtonTapped()

        val sent = session.sentFrames.single().clipboardText
        assertEquals("android", sent.originTag)
        assertEquals("hello mac", sent.text)
    }

    @Test
    fun foregroundCapture_noWindowFocus_clipboardReaderNeverCalled() {
        val session = FakeTandemSession()
        val reader = RecordingClipboardReader(ClipboardClip("hello mac", sensitive = false))
        val activity = buildAndCreate(session, reader)

        activity.onWindowFocusChanged(false)

        assertEquals(0, reader.callCount)
        assertTrue(session.sentFrames.isEmpty())
    }

    @Test
    fun foregroundCapture_sensitiveClipOnWindowFocus_notSent() {
        val session = FakeTandemSession()
        val reader = RecordingClipboardReader(ClipboardClip("secret", sensitive = true))
        val activity = buildAndCreate(session, reader)

        activity.onWindowFocusChanged(true)

        assertTrue(session.sentFrames.isEmpty())
    }

    @Test
    fun foregroundCapture_sensitiveClipViaButton_sentWithSensitiveFlag() {
        val session = FakeTandemSession()
        val reader = RecordingClipboardReader(ClipboardClip("secret", sensitive = true))
        val activity = buildAndCreate(session, reader)

        activity.onSendClipboardButtonTapped()

        val sent = session.sentFrames.single().clipboardText
        assertEquals("secret", sent.text)
        assertEquals(true, sent.sensitive)
    }

    @Test
    fun serviceStart_activityStartedWhilePaired_startsService() {
        var startCount = 0
        val controller = Robolectric.buildActivity(MainActivity::class.java)
        val activity = controller.get()
        activity.serviceStarterProvider = {
            ServiceStarter(FakePairedPeerRepository(hasPairedPeer = true)) { startCount++ }
        }
        activity.shellDependenciesProvider = { shellDependencies() }

        controller.create().start()

        assertEquals(1, startCount)
    }

    @Test
    fun serviceStart_activityStartedWhileUnpaired_doesNotStartService() {
        var startCount = 0
        val controller = Robolectric.buildActivity(MainActivity::class.java)
        val activity = controller.get()
        activity.serviceStarterProvider = {
            ServiceStarter(FakePairedPeerRepository(hasPairedPeer = false)) { startCount++ }
        }
        activity.shellDependenciesProvider = { shellDependencies() }

        controller.create().start()

        assertEquals(0, startCount)
    }

    @Test
    fun theme_mainActivity_hasNoActionBar() {
        val activity = buildAndCreate(FakeTandemSession(), RecordingClipboardReader(null))

        assertEquals(null, activity.actionBar)
    }

    private fun buildAndCreate(
        session: FakeTandemSession,
        reader: ClipboardReader,
    ): MainActivity {
        val controller = Robolectric.buildActivity(MainActivity::class.java)
        val activity = controller.get()
        activity.sessionProvider = { session }
        activity.dispatcher = UnconfinedTestDispatcher()
        activity.clipboardReaderProvider = { reader }
        activity.shellDependenciesProvider = { shellDependencies() }
        activity.serviceStarterProvider = { ServiceStarter(FakePairedPeerRepository(false)) {} }
        controller.create()
        return activity
    }

    private fun shellDependencies() =
        AppShellDependencies(
            peers = flowOf(emptyList()),
            statusLine = flowOf(""),
            ringState = MutableStateFlow(HomeRingState.Idle(itemsSyncedToday = 0, sevenDayAverage = 0)),
            onboarding =
                OnboardingViewModel(RecordingPermissionRequester(), FakePermissionChecker()),
            isBatteryRestricted = { false },
            addressStore = PairingAddressStore(File.createTempFile("addr", null)),
            pairingStarter = NoOpPairingStarter,
            unpair = {},
            onSendClipboard = {},
        )

    private class RecordingClipboardReader(
        private val clip: ClipboardClip?,
    ) : ClipboardReader {
        var callCount = 0
            private set

        override fun currentClip(): ClipboardClip? {
            callCount++
            return clip
        }
    }
}
