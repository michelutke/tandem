package dev.tandem.app.service

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.revoke.TrustRemover
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.revoke
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant

class ControlRevokeConsumerTest {
    private val peer = SpkiFingerprint(ByteArray(32) { 7 })

    @Test
    fun controlRevokeConsumer_revokeOnReadySession_trustRemovedAndSessionClosed() =
        runTest {
            val session = FakeTandemSession().apply { emitState(ConnectionState.Ready(Instant.EPOCH)) }
            val removed = mutableListOf<SpkiFingerprint>()
            session.emitIncoming(revokeEnvelope())

            consumeControlRevoke(RegisteredSession(session, peer), TrustRemover { removed += it })

            assertEquals(listOf(peer), removed)
            assertTrue(session.state.value is ConnectionState.Disconnected)
        }

    private fun revokeEnvelope() =
        envelope {
            channel = Channel.CHANNEL_CONTROL
            revoke = revoke {}
        }
}
