package dev.tandem.app.di

import com.google.protobuf.ByteString
import dev.tandem.app.settings.KeyRotationResult
import dev.tandem.core.crypto.ActiveIdentityAlias
import dev.tandem.core.crypto.IDENTITY_KEY_ALIAS
import dev.tandem.core.crypto.IdentityKeyProvider
import dev.tandem.core.crypto.SoftwareIdentityKeyStore
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.rotation.NextRotationDueStore
import dev.tandem.core.pairing.rotation.RotationKeys
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.testing.TestClock
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.envelope
import dev.tandem.protocol.v1.rotationAck
import dev.tandem.protocol.v1.rotationChallenge
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.time.Duration
import java.time.Instant

// unit (E70-15): appRotationComposition_settingsAndScheduler_shareOneInitiatorAndLock
@OptIn(ExperimentalCoroutinesApi::class)
class RotationCompositionTest {
    private class MemoryDueStore(
        var due: Instant?,
    ) : NextRotationDueStore {
        override fun get(): Instant? = due

        override fun set(due: Instant) {
            this.due = due
        }
    }

    private val session = FakeTandemSession()

    private fun composition(
        clock: TestClock,
        lock: Mutex = Mutex(),
    ): RotationComposition {
        val keyStore = SoftwareIdentityKeyStore(clock)
        keyStore.getOrCreate(IDENTITY_KEY_ALIAS, preferStrongBox = true)
        return RotationComposition(
            keys = RotationKeys(keyStore, IdentityKeyProvider(keyStore, logSecurityLevel = {}), ActiveIdentityAlias()),
            rotationLock = lock,
            pairingInProgress = { false },
        )
    }

    private fun challenge() =
        envelope {
            channel = Channel.CHANNEL_CONTROL
            rotationChallenge = rotationChallenge { challenge = ByteString.copyFrom(ByteArray(32) { 1 }) }
        }

    private fun ack() =
        envelope {
            channel = Channel.CHANNEL_CONTROL
            rotationAck = rotationAck {}
        }

    @Test
    fun appRotationComposition_settingsAndScheduler_shareOneInitiatorAndLock() =
        runTest {
            val clock = TestClock(testScheduler)
            val composition = composition(clock)
            session.emitState(ConnectionState.Ready(Instant.EPOCH))
            backgroundScope.launch {
                composition.sessionFeature().run(session, SpkiFingerprint(ByteArray(32)), null)
            }
            session.emitIncoming(challenge())
            runCurrent()
            assertTrue(composition.authenticated.value)

            backgroundScope.launch {
                composition.runScheduler(
                    clock,
                    MemoryDueStore(clock.instant().minusSeconds(1)),
                    flowOf(Duration.ofDays(365)),
                )
            }
            val settings = async { composition.keyRotator.rotate() }
            runCurrent()

            assertEquals(1, session.sentFrames.size)
            session.emitIncoming(ack())
            runCurrent()
            assertTrue(settings.await() is KeyRotationResult.Success)
            assertEquals(1, session.sentFrames.count { it.hasKeyRotation() })
        }

    @Test
    fun appRotationComposition_noSession_notAuthenticatedAndRotateFails() =
        runTest {
            val composition = composition(TestClock(testScheduler))

            assertFalse(composition.authenticated.value)
            assertTrue(composition.keyRotator.rotate() is KeyRotationResult.Failure)
        }

    @Test
    fun appRotationComposition_sessionEnds_notAuthenticated() =
        runTest {
            val composition = composition(TestClock(testScheduler))
            val job =
                backgroundScope.launch {
                    composition.sessionFeature().run(session, SpkiFingerprint(ByteArray(32)), null)
                }
            session.emitIncoming(challenge())
            runCurrent()
            assertTrue(composition.authenticated.value)

            job.cancel()
            runCurrent()

            assertFalse(composition.authenticated.value)
        }

    @Test
    fun appRotationComposition_sessionWithoutChallenge_notAuthenticated() =
        runTest {
            val composition = composition(TestClock(testScheduler))
            backgroundScope.launch {
                composition.sessionFeature().run(session, SpkiFingerprint(ByteArray(32)), null)
            }
            runCurrent()

            assertFalse(composition.authenticated.value)
        }

    @Test
    fun appRotationComposition_challengeArrivesAfterSchedulerStart_commits() =
        runTest {
            val clock = TestClock(testScheduler)
            val composition = composition(clock)
            session.emitState(ConnectionState.Ready(Instant.EPOCH))
            backgroundScope.launch {
                composition.sessionFeature().run(session, SpkiFingerprint(ByteArray(32)), null)
            }
            backgroundScope.launch {
                composition.runScheduler(
                    clock,
                    MemoryDueStore(clock.instant().minusSeconds(1)),
                    flowOf(Duration.ofDays(365)),
                )
            }
            runCurrent()
            assertEquals(0, session.sentFrames.size)

            session.emitIncoming(challenge())
            runCurrent()
            assertEquals(1, session.sentFrames.count { it.hasKeyRotation() })
            val before = composition.activeFingerprint.value
            session.emitIncoming(ack())
            runCurrent()

            assertTrue(composition.activeFingerprint.value != before)
        }

    @Test
    fun appRotationComposition_lockHeldElsewhere_rotationWaitsForIt() =
        runTest {
            val clock = TestClock(testScheduler)
            val lock = Mutex()
            val composition = composition(clock, lock)
            session.emitState(ConnectionState.Ready(Instant.EPOCH))
            backgroundScope.launch {
                composition.sessionFeature().run(session, SpkiFingerprint(ByteArray(32)), null)
            }
            session.emitIncoming(challenge())
            runCurrent()

            val reconnect = launch { lock.withLock { delay(10_000) } }
            runCurrent()
            val settings = async { composition.keyRotator.rotate() }
            runCurrent()
            assertEquals(0, session.sentFrames.size)

            reconnect.join()
            runCurrent()
            assertEquals(1, session.sentFrames.count { it.hasKeyRotation() })
            session.emitIncoming(ack())
            runCurrent()
            assertTrue(settings.await() is KeyRotationResult.Success)
        }
}
