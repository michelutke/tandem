package dev.tandem.core.pairing.rotation

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.ActiveIdentityAlias
import dev.tandem.core.crypto.IDENTITY_KEY_ALIAS
import dev.tandem.core.crypto.IdentityKeyManager
import dev.tandem.core.crypto.IdentityKeyProvider
import dev.tandem.core.crypto.RotationProof
import dev.tandem.core.crypto.SoftwareIdentityKeyStore
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.testing.TestClock
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.RotationRejectReason
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.rotationAck
import dev.tandem.protocol.v1.rotationChallenge
import dev.tandem.protocol.v1.rotationReject
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.time.Instant

private const val NEW_ALIAS = "tandem.identity.v2"

@OptIn(ExperimentalCoroutinesApi::class)
class RotationInitiatorTest {
    private val cb = ByteArray(32) { (it + 1).toByte() }

    private class Fixture(
        scope: TestScope,
        val session: FakeTandemSession = FakeTandemSession(),
        val keyStore: SoftwareIdentityKeyStore = SoftwareIdentityKeyStore(TestClock(scope.testScheduler)),
        val activeAlias: ActiveIdentityAlias = ActiveIdentityAlias(),
        var pairingInProgress: Boolean = false,
        peerPinned: Boolean = true,
    ) {
        val oldKey = keyStore.getOrCreate(IDENTITY_KEY_ALIAS, preferStrongBox = true)
        val initiator =
            RotationInitiator(
                session = session,
                keys = RotationKeys(keyStore, IdentityKeyProvider(keyStore, logSecurityLevel = {}), activeAlias),
                rotationLock = Mutex(),
                peerPinned = peerPinned,
                pairingInProgress = { pairingInProgress },
            )
    }

    private fun TestScope.fixture(
        peerPinned: Boolean = true,
        ready: Boolean = true,
        challenge: Boolean = true,
    ): Fixture {
        val fixture = Fixture(this, peerPinned = peerPinned)
        if (ready) fixture.session.emitState(ConnectionState.Ready(Instant.EPOCH))
        backgroundScope.launch { fixture.initiator.run() }
        if (challenge) fixture.session.emitIncoming(challengeEnvelope())
        runCurrent()
        return fixture
    }

    private fun challengeEnvelope() =
        envelope {
            channel = Channel.CHANNEL_CONTROL
            rotationChallenge = rotationChallenge { challenge = ByteString.copyFrom(cb) }
        }

    private fun ackEnvelope() =
        envelope {
            channel = Channel.CHANNEL_CONTROL
            rotationAck = rotationAck {}
        }

    private fun rejectEnvelope(reason: RotationRejectReason) =
        envelope {
            channel = Channel.CHANNEL_CONTROL
            rotationReject = rotationReject { this.reason = reason }
        }

    @Test
    fun rotate_sessionNotReady_sendsNothing() =
        runTest {
            val f = fixture(ready = false)

            assertEquals(RotationOutcome.NotAuthenticated, f.initiator.rotate())
            assertTrue(f.session.sentFrames.isEmpty())
            assertNull(f.keyStore.get(NEW_ALIAS))
        }

    @Test
    fun rotate_peerNotPinned_sendsNothing() =
        runTest {
            val f = fixture(peerPinned = false)

            assertEquals(RotationOutcome.NotAuthenticated, f.initiator.rotate())
            assertTrue(f.session.sentFrames.isEmpty())
        }

    @Test
    fun rotate_pairingInProgress_sendsNothing() =
        runTest {
            val f = fixture()
            f.pairingInProgress = true

            assertEquals(RotationOutcome.NotAuthenticated, f.initiator.rotate())
            assertTrue(f.session.sentFrames.isEmpty())
        }

    @Test
    fun rotate_noChallengeReceived_sendsNothing() =
        runTest {
            val f = fixture(challenge = false)

            assertEquals(RotationOutcome.NoChallenge, f.initiator.rotate())
            assertTrue(f.session.sentFrames.isEmpty())
            assertNull(f.keyStore.get(NEW_ALIAS))
        }

    @Test
    fun rotate_authenticatedSession_bothSignaturesVerifyOverTranscript() =
        runTest {
            val f = fixture()
            val outcome = async { f.initiator.rotate() }
            runCurrent()

            val sent =
                f.session.sentFrames
                    .single()
                    .keyRotation
            val newKey = requireNotNull(f.keyStore.get(NEW_ALIAS))
            assertEquals(newKey.publicKey.encoded.toList(), sent.newSpkiDer.toByteArray().toList())
            assertTrue(
                RotationProof.verify(
                    f.oldKey.publicKey.encoded,
                    sent.newSpkiDer.toByteArray(),
                    cb,
                    sent.sigOldKey.toByteArray(),
                    sent.sigNewKey.toByteArray(),
                ),
            )
            f.session.emitIncoming(ackEnvelope())
            runCurrent()
            assertEquals(RotationOutcome.Committed, outcome.await())
        }

    @Test
    fun rotate_beforeAck_oldKeyStaysActive() =
        runTest {
            val f = fixture()
            val outcome = async { f.initiator.rotate() }
            runCurrent()

            assertEquals(IDENTITY_KEY_ALIAS, f.activeAlias.current)
            assertNotNull(f.keyStore.get(IDENTITY_KEY_ALIAS))
            f.session.emitIncoming(ackEnvelope())
            runCurrent()
            outcome.await()
        }

    @Test
    fun rotate_afterAck_newKeyActiveOldAliasDeletedNextHandshakeUsesNewCert() =
        runTest {
            val f = fixture()
            val keyManager = IdentityKeyManager(f.keyStore, f.activeAlias)
            val outcome = async { f.initiator.rotate() }
            runCurrent()
            val newKey = requireNotNull(f.keyStore.get(NEW_ALIAS))

            f.session.emitIncoming(ackEnvelope())
            runCurrent()

            assertEquals(RotationOutcome.Committed, outcome.await())
            assertNull(f.keyStore.get(IDENTITY_KEY_ALIAS))
            assertEquals(NEW_ALIAS, f.activeAlias.current)
            assertEquals(
                newKey.publicKey.encoded.toList(),
                keyManager
                    .getCertificateChain(null)
                    .single()
                    .publicKey.encoded
                    .toList(),
            )
        }

    @Test
    fun rotate_rejected_oldKeyStaysActiveNewKeyDeleted() =
        runTest {
            val f = fixture()
            val outcome = async { f.initiator.rotate() }
            runCurrent()

            f.session.emitIncoming(rejectEnvelope(RotationRejectReason.ROTATION_REJECT_REASON_DUPLICATE_KEY))
            runCurrent()

            assertEquals(
                RotationOutcome.Rejected(RotationRejectReason.ROTATION_REJECT_REASON_DUPLICATE_KEY),
                outcome.await(),
            )
            assertEquals(IDENTITY_KEY_ALIAS, f.activeAlias.current)
            assertNotNull(f.keyStore.get(IDENTITY_KEY_ALIAS))
            assertNull(f.keyStore.get(NEW_ALIAS))
        }

    @Test
    fun rotate_noReplyWithin30s_timesOutKeepsOldActiveAndNewKeyForResend() =
        runTest {
            val f = fixture()
            val outcome = async { f.initiator.rotate() }
            runCurrent()

            advanceTimeBy(ROTATION_REPLY_TIMEOUT_MS + 1)
            runCurrent()

            assertEquals(RotationOutcome.TimedOut, outcome.await())
            assertEquals(IDENTITY_KEY_ALIAS, f.activeAlias.current)
            assertNotNull(f.keyStore.get(IDENTITY_KEY_ALIAS))
            assertNotNull(f.keyStore.get(NEW_ALIAS))
        }

    @Test
    fun rotate_afterLostAckOnNewSession_resendsSameNewSpki() =
        runTest {
            val first = fixture()
            val firstOutcome = async { first.initiator.rotate() }
            runCurrent()
            advanceTimeBy(ROTATION_REPLY_TIMEOUT_MS + 1)
            runCurrent()
            firstOutcome.await()
            val firstSpki =
                first.session.sentFrames
                    .single()
                    .keyRotation.newSpkiDer

            val secondSession = FakeTandemSession().apply { emitState(ConnectionState.Ready(Instant.EPOCH)) }
            val second =
                RotationInitiator(
                    session = secondSession,
                    keys =
                        RotationKeys(
                            first.keyStore,
                            IdentityKeyProvider(first.keyStore, logSecurityLevel = {}),
                            first.activeAlias,
                        ),
                    rotationLock = Mutex(),
                    peerPinned = true,
                    pairingInProgress = { false },
                )
            backgroundScope.launch { second.run() }
            secondSession.emitIncoming(challengeEnvelope())
            runCurrent()
            val secondOutcome = async { second.rotate() }
            runCurrent()
            secondSession.emitIncoming(ackEnvelope())
            runCurrent()

            assertEquals(
                firstSpki,
                secondSession.sentFrames
                    .single()
                    .keyRotation.newSpkiDer,
            )
            assertEquals(RotationOutcome.Committed, secondOutcome.await())
            assertEquals(NEW_ALIAS, first.activeAlias.current)
        }

    @Test
    fun rotate_challengeAlreadyConsumed_secondCallSendsNothing() =
        runTest {
            val f = fixture()
            val first = async { f.initiator.rotate() }
            runCurrent()
            f.session.emitIncoming(rejectEnvelope(RotationRejectReason.ROTATION_REJECT_REASON_ROTATION_UNAVAILABLE))
            runCurrent()
            first.await()

            assertEquals(RotationOutcome.NoChallenge, f.initiator.rotate())
            assertEquals(1, f.session.sentFrames.size)
        }

    @Test
    fun rotate_crashBeforeAck_restartedAliasStillOriginal(
        @TempDir dir: File,
    ) = runTest {
        val file = File(dir, "alias")
        val f = Fixture(this, activeAlias = ActiveIdentityAlias(file))
        f.session.emitState(ConnectionState.Ready(Instant.EPOCH))
        backgroundScope.launch { f.initiator.run() }
        f.session.emitIncoming(challengeEnvelope())
        runCurrent()
        backgroundScope.launch { f.initiator.rotate() }
        runCurrent()

        assertNotNull(f.keyStore.get(NEW_ALIAS))
        assertEquals(IDENTITY_KEY_ALIAS, ActiveIdentityAlias(file).current)
    }

    @Test
    fun rotate_afterAck_persistedAliasIsNewAlias(
        @TempDir dir: File,
    ) = runTest {
        val file = File(dir, "alias")
        val f = Fixture(this, activeAlias = ActiveIdentityAlias(file))
        f.session.emitState(ConnectionState.Ready(Instant.EPOCH))
        backgroundScope.launch { f.initiator.run() }
        f.session.emitIncoming(challengeEnvelope())
        runCurrent()
        val outcome = async { f.initiator.rotate() }
        runCurrent()
        f.session.emitIncoming(ackEnvelope())
        runCurrent()
        outcome.await()

        assertEquals(NEW_ALIAS, ActiveIdentityAlias(file).current)
    }
}
