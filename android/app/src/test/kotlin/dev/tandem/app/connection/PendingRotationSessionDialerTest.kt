package dev.tandem.app.connection

import dev.tandem.core.crypto.ActiveIdentityAlias
import dev.tandem.core.crypto.IDENTITY_KEY_ALIAS
import dev.tandem.core.crypto.SoftwareIdentityKeyStore
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.pairing.rotation.PendingRotationHandshake
import dev.tandem.core.protocol.connection.ConnectionFailure
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.testing.TestClock
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.core.transport.reconnect.CandidateAddress
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import java.time.Instant

// unit (E70-15): pendingRotationSessionDialer_oldKeyRejected_reconnectsWithPendingKey
@OptIn(ExperimentalCoroutinesApi::class)
class PendingRotationSessionDialerTest {
    private val candidate = CandidateAddress("192.0.2.1", 4433)
    private val readySession = FakeTandemSession().apply { emitState(ConnectionState.Ready(Instant.EPOCH)) }
    private val connected = DialResult.Connected(readySession, SpkiFingerprint(ByteArray(32)))
    private val rejected = DialResult.Unreachable(ConnectionFailure.HandshakeError("REVOKED"))
    private val dialedAliases = mutableListOf<String>()

    private fun TestScopeFixture.dialer(onAuthenticated: () -> Unit = {}) =
        PendingRotationSessionDialer(
            handshake = PendingRotationHandshake(keyStore, activeAlias, Mutex()),
            dialerFor = { alias ->
                SessionDialer {
                    dialedAliases += alias
                    if (alias == IDENTITY_KEY_ALIAS) rejected else connected
                }
            },
            onAuthenticated = onAuthenticated,
        )

    private class TestScopeFixture(
        val keyStore: SoftwareIdentityKeyStore,
        val activeAlias: ActiveIdentityAlias = ActiveIdentityAlias(),
    )

    @Test
    fun pendingRotationSessionDialer_oldKeyRejected_reconnectsWithPendingKey() =
        runTest {
            val keyStore = SoftwareIdentityKeyStore(TestClock(testScheduler))
            keyStore.getOrCreate(IDENTITY_KEY_ALIAS, preferStrongBox = true)
            val fixture = TestScopeFixture(keyStore)
            val pendingAlias = fixture.activeAlias.nextAlias()
            keyStore.getOrCreate(pendingAlias, preferStrongBox = true)
            var authenticated = 0

            val result = fixture.dialer { authenticated++ }.dial(candidate)

            assertEquals(connected, result)
            assertEquals(listOf(IDENTITY_KEY_ALIAS, pendingAlias), dialedAliases)
            assertEquals(pendingAlias, fixture.activeAlias.current)
            assertNull(keyStore.get(IDENTITY_KEY_ALIAS))
            assertEquals(1, authenticated)
        }

    @Test
    fun pendingRotationSessionDialer_noPendingKey_returnsRejectionUnchanged() =
        runTest {
            val keyStore = SoftwareIdentityKeyStore(TestClock(testScheduler))
            keyStore.getOrCreate(IDENTITY_KEY_ALIAS, preferStrongBox = true)
            val fixture = TestScopeFixture(keyStore)

            val result = fixture.dialer().dial(candidate)

            assertEquals(rejected, result)
            assertEquals(listOf(IDENTITY_KEY_ALIAS), dialedAliases)
            assertEquals(IDENTITY_KEY_ALIAS, fixture.activeAlias.current)
        }
}
