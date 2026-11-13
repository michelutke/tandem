package dev.tandem.app.service

import android.app.ForegroundServiceStartNotAllowedException
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.app.connection.NoOpConnectionLoop
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf

// Android 12+ refuses a foreground start from the background (no battery-optimisation exemption);
// the refusal must end quietly instead of crash-looping the process. Robolectric (E00-20): the
// exception and Service are Android framework types.
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class ForegroundStartNotAllowedTest {
    @Test
    fun tandemService_startForegroundNotAllowed_stopsSelfWithoutCrash() {
        val controller = Robolectric.buildService(TandemService::class.java)
        val service = controller.get()
        service.pairedPeerRepositoryFactory = { FakePairedPeerRepository(MutableStateFlow(true)) }
        service.connectionLoopFactory = { NoOpConnectionLoop }
        service.dispatcher = UnconfinedTestDispatcher()
        service.startInForeground = { throw ForegroundServiceStartNotAllowedException("background start") }

        controller.create()

        assertTrue(shadowOf(service).isStoppedBySelf)
    }

    @Test
    fun serviceStarter_foregroundStartNotAllowed_startAndKeepStartedDoNotThrow() {
        var attempts = 0
        val starter =
            ServiceStarter(FakePairedPeerRepository(hasPairedPeer = true)) {
                attempts++
                throw ForegroundServiceStartNotAllowedException("background start")
            }

        runBlocking { starter.start() }
        assertEquals(1, attempts)

        runBlocking { withTimeoutOrNull(KEEP_STARTED_WINDOW_MS) { starter.keepStarted() } }

        assertEquals(2, attempts)
    }

    private companion object {
        const val KEEP_STARTED_WINDOW_MS = 200L
    }
}
