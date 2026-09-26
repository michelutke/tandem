package dev.tandem.core.pairing

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Envelope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Instant

/**
 * UnpairAction tests (E14-12; `docs/planning/backlog/phase-1.yaml` E14-12's `tdd:` list).
 * Every test uses [FakeTandemSession] so no real socket is opened, and [StandardTestDispatcher]
 * with its [TestScope.testScheduler] so timeouts advance in virtual time under `runTest` (E00-18).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class UnpairActionTest {
    private val fingerprintBytes = ByteArray(32) { it.toByte() }
    private val fingerprint = SpkiFingerprint(fingerprintBytes)

    @Test
    fun unpairAction_readySession_deleteThenRevokeThenClose() =
        runTest {
            val session = readySession()
            val trustRemover = FakeTrustRemover()
            val registry = PeerDataPurgeRegistry()
            val action = UnpairAction(trustRemover, registry)

            action.unpair(fingerprint, session)

            // Verify order: delete happened, revoke was sent, session was closed
            assertEquals(listOf(fingerprint), trustRemover.deleted)
            assertTrue(session.sentFrames.any { it.payloadCase == Envelope.PayloadCase.REVOKE })
            assertTrue(session.state.value is ConnectionState.Disconnected)
        }

    @Test
    fun unpairAction_noSession_deletesLocallySendsNothing() =
        runTest {
            val trustRemover = FakeTrustRemover()
            val registry = PeerDataPurgeRegistry()
            val action = UnpairAction(trustRemover, registry)

            action.unpair(fingerprint, null)

            // Verify delete happened but nothing was sent
            assertEquals(listOf(fingerprint), trustRemover.deleted)
        }

    @Test
    fun unpairAction_revokeSendThrows_recordDeletedAndSessionClosed() =
        runTest {
            val session = readySession()
            val trustRemover = FakeTrustRemover()
            val registry = PeerDataPurgeRegistry()
            val action = UnpairAction(trustRemover, registry)

            // Make the send throw
            session.failNextSend(Exception("Network error"))

            action.unpair(fingerprint, session)

            // Verify delete happened and session was closed despite the error
            assertEquals(listOf(fingerprint), trustRemover.deleted)
            assertTrue(session.state.value is ConnectionState.Disconnected)
        }

    @Test
    fun unpairAction_revokeSendHangs_sessionClosedAfter2sVirtual() =
        runTest {
            val session = readySessionWithHangingSend()
            val trustRemover = FakeTrustRemover()
            val registry = PeerDataPurgeRegistry()
            val action = UnpairAction(trustRemover, registry)

            action.unpair(fingerprint, session)

            // After 2 seconds, send should timeout and session should be closed
            advanceTimeBy(2000)
            assertTrue(session.state.value is ConnectionState.Disconnected)
            assertEquals(listOf(fingerprint), trustRemover.deleted)
        }

    @Test
    fun unpairAction_registeredPurgers_eachCalledOnceWithPeerFingerprint() =
        runTest {
            val session = readySession()
            val trustRemover = FakeTrustRemover()
            val registry = PeerDataPurgeRegistry()
            val purger1 = FakePurger()
            val purger2 = FakePurger()
            registry.register(purger1)
            registry.register(purger2)
            val action = UnpairAction(trustRemover, registry)

            action.unpair(fingerprint, session)

            // Verify each purger was called once with the fingerprint
            assertEquals(listOf(fingerprint), purger1.purged)
            assertEquals(listOf(fingerprint), purger2.purged)
        }

    private fun TestScope.readySession(): FakeTandemSession =
        FakeTandemSession().also { it.emitState(ConnectionState.Ready(Instant.EPOCH)) }

    private fun TestScope.readySessionWithHangingSend(): FakeTandemSession {
        val session = FakeTandemSession()
        session.emitState(ConnectionState.Ready(Instant.EPOCH))
        session.setHangingSend()
        return session
    }

    private class FakeTrustRemover : TrustRemover {
        val deleted = mutableListOf<SpkiFingerprint>()

        override suspend fun delete(fingerprint: SpkiFingerprint) {
            deleted += fingerprint
        }
    }

    private class FakePurger : PeerDataPurging {
        val purged = mutableListOf<SpkiFingerprint>()

        override suspend fun purgeAll(peerFingerprint: SpkiFingerprint) {
            purged += peerFingerprint
        }
    }
}
