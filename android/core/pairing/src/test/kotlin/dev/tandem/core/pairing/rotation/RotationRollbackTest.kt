package dev.tandem.core.pairing.rotation

import com.google.protobuf.ByteString
import dev.tandem.core.crypto.ActiveIdentityAlias
import dev.tandem.core.crypto.IDENTITY_KEY_ALIAS
import dev.tandem.core.crypto.IdentityKeyProvider
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
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.time.Instant

private const val NEW_ALIAS = "tandem.identity.v2"

@OptIn(ExperimentalCoroutinesApi::class)
class RotationRollbackTest {
    private val cb = ByteArray(32) { (it + 1).toByte() }

    private class Env(
        scope: TestScope,
        aliasFile: File? = null,
        val keyStore: SoftwareIdentityKeyStore = SoftwareIdentityKeyStore(TestClock(scope.testScheduler)),
    ) {
        val activeAlias = ActiveIdentityAlias(aliasFile)

        init {
            keyStore.getOrCreate(IDENTITY_KEY_ALIAS, preferStrongBox = true)
        }

        val rotationLock = Mutex()

        fun handshake() = PendingRotationHandshake(keyStore, activeAlias, rotationLock)

        fun initiator(session: FakeTandemSession) =
            RotationInitiator(
                session = session,
                keys = RotationKeys(keyStore, IdentityKeyProvider(keyStore, logSecurityLevel = {}), activeAlias),
                rotationLock = rotationLock,
                peerPinned = true,
                pairingInProgress = { false },
            )
    }

    private fun TestScope.readySession(
        initiator: (FakeTandemSession) -> RotationInitiator,
    ): Pair<FakeTandemSession, RotationInitiator> {
        val session = FakeTandemSession().apply { emitState(ConnectionState.Ready(Instant.EPOCH)) }
        val rotation = initiator(session)
        backgroundScope.launch { rotation.run() }
        session.emitIncoming(
            envelope {
                channel = Channel.CHANNEL_CONTROL
                rotationChallenge = rotationChallenge { challenge = ByteString.copyFrom(cb) }
            },
        )
        runCurrent()
        return session to rotation
    }

    @Test
    fun androidRotationRollback_noAckWithin30s_oldKeyRemainsActiveIdentity() =
        runTest {
            val env = Env(this)
            val (_, rotation) = readySession(env::initiator)
            val outcome = async { rotation.rotate() }
            runCurrent()

            advanceTimeBy(ROTATION_REPLY_TIMEOUT_MS + 1)
            runCurrent()

            assertEquals(RotationOutcome.TimedOut, outcome.await())
            assertEquals(IDENTITY_KEY_ALIAS, env.activeAlias.current)
            assertNotNull(env.keyStore.get(IDENTITY_KEY_ALIAS))
        }

    @Test
    fun androidRotationRollback_nextSessionAfterTimeout_resendsSamePendingNewSpki() =
        runTest {
            val env = Env(this)
            val (first, firstRotation) = readySession(env::initiator)
            val firstOutcome = async { firstRotation.rotate() }
            runCurrent()
            advanceTimeBy(ROTATION_REPLY_TIMEOUT_MS + 1)
            runCurrent()
            firstOutcome.await()

            val (second, secondRotation) = readySession(env::initiator)
            val secondOutcome = async { secondRotation.rotate() }
            runCurrent()

            assertEquals(
                first.sentFrames
                    .single()
                    .keyRotation.newSpkiDer,
                second.sentFrames
                    .single()
                    .keyRotation.newSpkiDer,
            )
            second.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_CONTROL
                    rotationAck = rotationAck {}
                },
            )
            runCurrent()
            assertEquals(RotationOutcome.Committed, secondOutcome.await())
        }

    @Test
    fun androidRotationRollback_rotationRejectReceived_pendingKeyDeletedOldKeySole() =
        runTest {
            val env = Env(this)
            val (session, rotation) = readySession(env::initiator)
            val outcome = async { rotation.rotate() }
            runCurrent()

            session.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_CONTROL
                    rotationReject =
                        rotationReject { reason = RotationRejectReason.ROTATION_REJECT_REASON_DUPLICATE_KEY }
                },
            )
            runCurrent()

            assertTrue(outcome.await() is RotationOutcome.Rejected)
            assertNull(env.keyStore.get(NEW_ALIAS))
            assertNotNull(env.keyStore.get(IDENTITY_KEY_ALIAS))
            assertEquals(IDENTITY_KEY_ALIAS, env.activeAlias.current)
        }

    @Test
    fun androidRotationRollback_sessionDropBeforeAck_rotationStaysPending() =
        runTest {
            val env = Env(this)
            val (session, rotation) = readySession(env::initiator)
            val outcome = async { rotation.rotate() }
            runCurrent()

            session.close()
            runCurrent()

            assertEquals(RotationOutcome.SessionDropped, outcome.await())
            assertEquals(IDENTITY_KEY_ALIAS, env.activeAlias.current)
            assertNotNull(env.keyStore.get(IDENTITY_KEY_ALIAS))
            assertNotNull(env.keyStore.get(NEW_ALIAS))
        }

    @Test
    fun androidRotationRollback_processRestart_pendingRotationResent(
        @TempDir dir: File,
    ) = runTest {
        val aliasFile = File(dir, "alias")
        val env = Env(this, aliasFile)
        val (first, firstRotation) = readySession(env::initiator)
        backgroundScope.launch { firstRotation.rotate() }
        runCurrent()
        val pendingSpki =
            first.sentFrames
                .single()
                .keyRotation.newSpkiDer

        val restarted = Env(this, aliasFile, env.keyStore)
        val (second, secondRotation) = readySession(restarted::initiator)
        backgroundScope.launch { secondRotation.rotate() }
        runCurrent()

        assertEquals(IDENTITY_KEY_ALIAS, restarted.activeAlias.current)
        assertEquals(
            pendingSpki,
            second.sentFrames
                .single()
                .keyRotation.newSpkiDer,
        )
    }

    @Test
    fun androidRotationRollback_oldKeyRejectedWhilePending_retriesOnceWithPendingKey() =
        runTest {
            val env = Env(this)
            env.keyStore.getOrCreate(NEW_ALIAS, preferStrongBox = true)
            val aliasesTried = mutableListOf<String>()

            val connected =
                env.handshake().connect { alias ->
                    aliasesTried += alias
                    if (alias == NEW_ALIAS) HandshakeResult.Accepted(true) else HandshakeResult.Rejected
                }

            assertTrue(connected)
            assertEquals(listOf(IDENTITY_KEY_ALIAS, NEW_ALIAS), aliasesTried)
            assertEquals(NEW_ALIAS, env.activeAlias.current)
            assertNull(env.keyStore.get(IDENTITY_KEY_ALIAS))
        }

    @Test
    fun androidRotationRollback_rotateRejectedDuringPendingHandshake_pendingKeyStaysActive() =
        runTest {
            val env = Env(this)
            env.keyStore.getOrCreate(NEW_ALIAS, preferStrongBox = true)
            val (session, rotation) = readySession(env::initiator)

            var rotated: Deferred<RotationOutcome>? = null
            val connected =
                env.handshake().connect { alias ->
                    if (alias == NEW_ALIAS) {
                        rotated = backgroundScope.async { rotation.rotate() }
                        runCurrent()
                        HandshakeResult.Accepted(true)
                    } else {
                        HandshakeResult.Rejected
                    }
                }
            runCurrent()
            session.emitIncoming(
                envelope {
                    channel = Channel.CHANNEL_CONTROL
                    rotationReject =
                        rotationReject { reason = RotationRejectReason.ROTATION_REJECT_REASON_DUPLICATE_KEY }
                },
            )
            runCurrent()

            assertTrue(connected)
            assertEquals(NEW_ALIAS, env.activeAlias.current)
            assertNotNull(env.keyStore.get(NEW_ALIAS))
            assertNull(env.keyStore.get(IDENTITY_KEY_ALIAS))
            assertTrue(rotated?.isCompleted == true)
            assertTrue(rotated?.getCompleted() is RotationOutcome.Rejected)
            assertNull(env.keyStore.get("tandem.identity.v3"))
        }

    @Test
    fun androidRotationRollback_bothKeysRejected_oldKeyRestoredNoNewKeyGenerated() =
        runTest {
            val env = Env(this)
            env.keyStore.getOrCreate(NEW_ALIAS, preferStrongBox = true)
            var attempts = 0

            val connected = env.handshake().connect { attempts++.let { HandshakeResult.Rejected } }

            assertFalse(connected)
            assertEquals(2, attempts)
            assertEquals(IDENTITY_KEY_ALIAS, env.activeAlias.current)
            assertNotNull(env.keyStore.get(IDENTITY_KEY_ALIAS))
        }

    @Test
    fun androidRotationRollback_oldKeyRejectedNoPending_noRetry() =
        runTest {
            val env = Env(this)
            var attempts = 0

            val connected = env.handshake().connect { attempts++.let { HandshakeResult.Rejected } }

            assertFalse(connected)
            assertEquals(1, attempts)
            assertNull(env.keyStore.get(NEW_ALIAS))
        }

    @Test
    fun androidRotationRollback_networkErrorWhilePending_noRetryOldKeyKept() =
        runTest {
            val env = Env(this)
            env.keyStore.getOrCreate(NEW_ALIAS, preferStrongBox = true)
            var attempts = 0

            val connected = env.handshake().connect { attempts++.let { HandshakeResult.NetworkError } }
            val accepted = env.handshake().connect { HandshakeResult.Accepted(true) }

            assertFalse(connected)
            assertEquals(1, attempts)
            assertTrue(accepted)
            assertEquals(IDENTITY_KEY_ALIAS, env.activeAlias.current)
            assertNotNull(env.keyStore.get(IDENTITY_KEY_ALIAS))
        }

    @Test
    fun androidRotationRollback_pendingKeyAcceptedUnauthenticated_noCommit() =
        runTest {
            val env = Env(this)
            env.keyStore.getOrCreate(NEW_ALIAS, preferStrongBox = true)

            val connected =
                env.handshake().connect { alias ->
                    if (alias == NEW_ALIAS) HandshakeResult.Accepted(false) else HandshakeResult.Rejected
                }

            assertFalse(connected)
            assertEquals(IDENTITY_KEY_ALIAS, env.activeAlias.current)
            assertNotNull(env.keyStore.get(IDENTITY_KEY_ALIAS))
            assertNotNull(env.keyStore.get(NEW_ALIAS))
        }

    @Test
    fun androidRotationRollback_crashDuringPendingRetry_restartUsesOldKey(
        @TempDir dir: File,
    ) = runTest {
        val aliasFile = File(dir, "alias")
        val env = Env(this, aliasFile)
        env.keyStore.getOrCreate(NEW_ALIAS, preferStrongBox = true)

        env.handshake().connect { alias ->
            if (alias == NEW_ALIAS) {
                assertEquals(IDENTITY_KEY_ALIAS, ActiveIdentityAlias(aliasFile).current)
            }
            HandshakeResult.Rejected
        }

        assertEquals(IDENTITY_KEY_ALIAS, ActiveIdentityAlias(aliasFile).current)
        assertNotNull(env.keyStore.get(IDENTITY_KEY_ALIAS))
    }
}
