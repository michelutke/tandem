package dev.tandem.app.service

import android.app.Service
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf

// E20-02 tdd:
//   unit: tandemService_lastMacUnpaired_stopsAndRemovesNotification
//   unit: tandemService_onStartCommand_returnsStartSticky
//
// Runs on Robolectric (E00-20): TandemService is an android.app.Service, an Android framework
// type Robolectric models via ServiceController. pairedPeerRepositoryFactory/dispatcher are set
// on the controller-attached-but-not-yet-created instance (Robolectric.buildService attaches a
// real Context but does not call onCreate() until .create()), so onCreate() picks up the fake
// repository and an unconfined test dispatcher instead of the production TrustStore-backed one.
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class TandemServiceTest {
    @Test
    fun tandemService_onStartCommand_returnsStartSticky() {
        val service = buildService(hasPairedPeer = true)

        val result = service.onStartCommand(null, 0, 0)

        assertEquals(Service.START_STICKY, result)
    }

    @Test
    fun tandemService_lastMacUnpaired_stopsAndRemovesNotification() {
        val hasPairedPeer = MutableStateFlow(true)
        val service = buildService(hasPairedPeer)
        val shadowService = shadowOf(service)
        assertTrue("precondition: service starts in the foreground", shadowService.lastForegroundNotification != null)

        hasPairedPeer.value = false

        assertTrue(shadowService.isForegroundStopped)
        assertTrue(shadowService.notificationShouldRemoved)
        assertTrue(shadowService.isStoppedBySelf)
    }

    private fun buildService(hasPairedPeer: Boolean): TandemService = buildService(MutableStateFlow(hasPairedPeer))

    private fun buildService(hasPairedPeer: MutableStateFlow<Boolean>): TandemService {
        val controller = Robolectric.buildService(TandemService::class.java)
        val service = controller.get()
        service.pairedPeerRepositoryFactory = { FakePairedPeerRepository(hasPairedPeer) }
        service.dispatcher = UnconfinedTestDispatcher()
        controller.create()
        return service
    }
}
