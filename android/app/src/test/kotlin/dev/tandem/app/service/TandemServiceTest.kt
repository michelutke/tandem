package dev.tandem.app.service

import android.app.Service
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.app.TandemApplication
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.revoke.TrustRemover
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.storage.trust.PeerRecord
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.revoke
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import java.time.Instant

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

    // Regression test: TandemService's default pairedPeerRepositoryFactory must read the one
    // process-wide TrustStore instance TandemApplication holds (`applicationContext as
    // TandemApplication).trustStore`), not open its own connection to the same file -- Room's
    // InvalidationTracker (what TrustStore.observeList's reactivity relies on) is scoped per
    // RoomDatabase instance, so a second connection would never see a write made through the
    // first, and the service would never stop. This test does *not* override
    // pairedPeerRepositoryFactory, exercising the real production wiring, and unpairs through
    // TandemApplication.trustStore directly (standing in for a future consumer such as an unpair
    // action elsewhere in :app) rather than through the service.
    @Test
    fun tandemService_unpairedThroughSharedTrustStore_stopsAndRemovesNotification() {
        val trustStore = (RuntimeEnvironment.getApplication() as TandemApplication).trustStore
        val fingerprint = SpkiFingerprint(ByteArray(32) { 1 })
        runBlocking {
            trustStore.put(
                PeerRecord(
                    deviceId = "device-1",
                    displayName = "Mac",
                    spkiSha256Base64Url = fingerprint.base64Url,
                    pairedAtEpochMs = 0L,
                    lastSeenEpochMs = 0L,
                    capabilities = emptyList(),
                ),
            )
        }

        val controller = Robolectric.buildService(TandemService::class.java)
        val service = controller.get()
        service.dispatcher = UnconfinedTestDispatcher()
        controller.create()
        val shadowService = shadowOf(service)
        assertTrue("precondition: service starts in the foreground", shadowService.lastForegroundNotification != null)

        runBlocking { trustStore.unpair(fingerprint) }

        // Room's InvalidationTracker notices the delete and re-runs observeList()'s query on its
        // own executor, asynchronously from this test thread (unlike FakePairedPeerRepository's
        // MutableStateFlow in the other test, which updates synchronously under
        // UnconfinedTestDispatcher); poll with a bounded timeout instead of asserting immediately.
        awaitTrue(timeoutMs = 10_000) { shadowService.isStoppedBySelf }

        assertTrue(shadowService.isForegroundStopped)
        assertTrue(shadowService.notificationShouldRemoved)
        assertTrue(shadowService.isStoppedBySelf)
    }

    @Test
    fun tandemService_revokeFrameOnRegisteredSession_trustRemovedAndSessionClosed() {
        val peer = SpkiFingerprint(ByteArray(32) { 3 })
        val session = FakeTandemSession().apply { emitState(ConnectionState.Ready(Instant.EPOCH)) }
        val registry = SessionRegistry()
        val removed = mutableListOf<SpkiFingerprint>()
        val controller = Robolectric.buildService(TandemService::class.java)
        controller.get().apply {
            pairedPeerRepositoryFactory = { FakePairedPeerRepository(MutableStateFlow(true)) }
            sessionRegistryFactory = { registry }
            trustRemoverFactory = { TrustRemover { removed += it } }
            dispatcher = UnconfinedTestDispatcher()
        }
        controller.create()
        registry.register(session, peer)

        session.emitIncoming(
            envelope {
                channel = Channel.CHANNEL_CONTROL
                revoke = revoke {}
            },
        )

        assertEquals(listOf(peer), removed)
        assertTrue(session.state.value is ConnectionState.Disconnected)
    }

    private fun awaitTrue(
        timeoutMs: Long,
        condition: () -> Boolean,
    ) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (!condition() && System.currentTimeMillis() < deadline) {
            Thread.sleep(10)
        }
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
