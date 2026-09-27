package dev.tandem.core.pairing.revoke

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.FakeTandemSession
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant

class RevokeHandlerTest {
    private val peer = SpkiFingerprint(ByteArray(FINGERPRINT_BYTES) { 7 })
    private val removed = mutableListOf<SpkiFingerprint>()
    private val session = FakeTandemSession()
    private val handler =
        RevokeHandler(session, peer) { fingerprint ->
            assertTrue(session.state.value is ConnectionState.Ready, "trust removed before close")
            removed += fingerprint
        }

    @Test
    fun revokeHandler_revokeOnReadySession_deletesMacRecordAndCloses() =
        runTest {
            session.emitState(ConnectionState.Ready(Instant.EPOCH))

            assertTrue(handler.handleRevoke())

            assertEquals(listOf(peer), removed)
            assertTrue(session.state.value is ConnectionState.Disconnected)
        }

    @Test
    fun revokeHandler_revokeBeforeReady_ignoredTrustStoreUnchanged() =
        runTest {
            session.emitState(ConnectionState.HelloExchange)

            assertFalse(handler.handleRevoke())

            assertTrue(removed.isEmpty())
            assertEquals(ConnectionState.HelloExchange, session.state.value)
        }

    private companion object {
        const val FINGERPRINT_BYTES = 32
    }
}
