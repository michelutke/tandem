package dev.tandem.app.service

import android.app.Application
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.tandem.app.TandemApplication
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.storage.trust.PeerRecord
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.revoke
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant

// E20-21 tdd:
//   instrumented: tandemService_revokeFrameReceived_trustDeletedAndSessionClosedWithin2s
//
// Starts the real TandemService on a device/emulator against the process-wide TandemApplication
// trust store and session registry, registers a FakeTandemSession (no composition root dials a
// real one yet) and delivers a Revoke on its CONTROL channel.
@RunWith(AndroidJUnit4::class)
class TandemServiceRevokeInstrumentedTest {
    private val application = ApplicationProvider.getApplicationContext<Application>() as TandemApplication

    @Test
    fun tandemService_revokeFrameReceived_trustDeletedAndSessionClosedWithin2s() {
        val peer = SpkiFingerprint(ByteArray(32) { 5 })
        runBlocking {
            application.trustStore.put(
                PeerRecord(
                    deviceId = "device-revoke",
                    displayName = "Mac",
                    spkiSha256Base64Url = peer.base64Url,
                    pairedAtEpochMs = 0L,
                    lastSeenEpochMs = 0L,
                    capabilities = emptyList(),
                ),
            )
        }
        application.startForegroundService(Intent(application, TandemService::class.java))
        val session = FakeTandemSession().apply { emitState(ConnectionState.Ready(Instant.EPOCH)) }
        application.sessionRegistry.register(session, peer)

        session.emitIncoming(
            envelope {
                channel = Channel.CHANNEL_CONTROL
                revoke = revoke {}
            },
        )

        val deadline = System.nanoTime() + 2_000_000_000L
        while (session.state.value !is ConnectionState.Disconnected && System.nanoTime() < deadline) {
            Thread.sleep(10)
        }
        assertTrue(session.state.value is ConnectionState.Disconnected)
        assertNull(runBlocking { application.trustStore.get(peer) })
    }
}
