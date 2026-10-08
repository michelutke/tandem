package dev.tandem.app.connection

import dev.tandem.app.service.SessionRegistry
import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.discovery.DiscoveryEvent
import dev.tandem.core.discovery.PairedMacMatcher
import dev.tandem.core.discovery.ServiceDiscovery
import dev.tandem.core.protocol.connection.ConnectionFailure
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.testing.TestClock
import dev.tandem.core.transport.FakeTandemSession
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.heartbeat.DeviceIdleSource
import dev.tandem.core.transport.reconnect.CandidateAddress
import dev.tandem.core.transport.reconnect.NetworkMonitor
import dev.tandem.core.transport.reconnect.PairedMacBonjourSource
import dev.tandem.core.transport.reconnect.PairingAddressSource
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.time.Instant

// unit: tandemServiceComposition_sessionReady_allFeatureConsumersAttachedOnce
// unit: tandemServiceComposition_sessionClosed_consumersDetached
@OptIn(ExperimentalCoroutinesApi::class)
class ConnectionOrchestratorTest {
    private val peer = SpkiFingerprint(ByteArray(32) { 5 })

    private class CountingFeature : SessionFeature {
        var attached = 0
        var detached = 0
        val sessions = mutableListOf<TandemSession>()

        override suspend fun run(
            session: TandemSession,
            peer: SpkiFingerprint,
            peerSpkiDer: ByteArray?,
        ) {
            attached++
            sessions += session
            try {
                awaitCancellation()
            } finally {
                detached++
            }
        }
    }

    private class ScriptedDialer(
        private val results: MutableList<DialResult>,
    ) : SessionDialer {
        var dials = 0

        override suspend fun dial(candidate: CandidateAddress): DialResult {
            dials++
            return if (results.isEmpty()) DialResult.Unreachable(null) else results.removeAt(0)
        }
    }

    private class Harness(
        scope: TestScope,
        val dialer: SessionDialer,
        val features: List<CountingFeature>,
        directory: File,
        knownPeersFile: File = File(directory, "known-peers"),
    ) {
        val registry = SessionRegistry()
        val screenOn = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
        val knownPeers = KnownPeerStore(knownPeersFile)
        val orchestrator =
            ConnectionOrchestrator(
                dialer = dialer,
                registry = registry,
                featureAttacher = FeatureAttacher(features) {},
                knownPeerStore = knownPeers,
                bonjourSource =
                    PairedMacBonjourSource(
                        object : ServiceDiscovery {
                            override fun browse(): Flow<DiscoveryEvent> = emptyFlow()
                        },
                        PairedMacMatcher(TestClock(scope.testScheduler)),
                        { emptyList() },
                        StandardTestDispatcher(scope.testScheduler),
                    ),
                pairingAddressSource = PairingAddressSource { listOf(CandidateAddress("192.0.2.1", 7000)) },
                networkMonitor =
                    object : NetworkMonitor {
                        override val available: Flow<Unit> = emptyFlow()
                    },
                deviceIdleSource =
                    object : DeviceIdleSource {
                        override val isIdle: StateFlow<Boolean> = MutableStateFlow(false)
                        override val screenOn: Flow<Unit> = this@Harness.screenOn
                    },
                foreground = emptyFlow(),
                clock = TestClock(scope.testScheduler),
                dispatcher = StandardTestDispatcher(scope.testScheduler),
            )
    }

    private fun readySession() = FakeTandemSession().apply { emitState(ConnectionState.Ready(Instant.EPOCH)) }

    @Test
    fun tandemServiceComposition_sessionReady_allFeatureConsumersAttachedOnce(
        @TempDir directory: File,
    ) = runTest {
        val session = readySession()
        val features = listOf(CountingFeature(), CountingFeature())
        val dialer = ScriptedDialer(mutableListOf(DialResult.Connected(session, peer)))
        val harness = Harness(this, dialer, features, directory)

        harness.orchestrator.start()
        runCurrent()

        assertSame(
            session,
            harness.registry.current.value
                ?.session,
        )
        assertEquals(listOf(1, 1), features.map { it.attached })
        assertTrue(harness.knownPeers.hasEverPinned(peer))
        assertNull(harness.orchestrator.failure.value)
        harness.orchestrator.close()
    }

    @Test
    fun tandemServiceComposition_knownPeerPersistenceFails_sessionStillAttached(
        @TempDir directory: File,
    ) = runTest {
        val session = readySession()
        val features = listOf(CountingFeature())
        val dialer = ScriptedDialer(mutableListOf(DialResult.Connected(session, peer)))
        val blocker = File(directory, "blocker").apply { writeText("") }
        val harness = Harness(this, dialer, features, directory, File(blocker, "known-peers"))

        harness.orchestrator.start()
        runCurrent()

        assertSame(
            session,
            harness.registry.current.value
                ?.session,
        )
        assertEquals(listOf(1), features.map { it.attached })
        harness.orchestrator.close()
    }

    @Test
    fun tandemServiceComposition_sessionClosed_consumersDetached(
        @TempDir directory: File,
    ) = runTest {
        val first = readySession()
        val second = readySession()
        val features = listOf(CountingFeature())
        val dialer =
            ScriptedDialer(mutableListOf(DialResult.Connected(first, peer), DialResult.Connected(second, peer)))
        val harness = Harness(this, dialer, features, directory)
        harness.orchestrator.start()
        runCurrent()

        first.close()
        runCurrent()

        assertEquals(1, features[0].detached)
        assertEquals(listOf(first, second), features[0].sessions)
        assertEquals(2, features[0].attached)
        assertSame(
            second,
            harness.registry.current.value
                ?.session,
        )
        harness.orchestrator.close()
    }

    @Test
    fun tandemServiceComposition_stopped_detachesConsumersAndClosesSession(
        @TempDir directory: File,
    ) = runTest {
        val session = readySession()
        val features = listOf(CountingFeature())
        val dialer = ScriptedDialer(mutableListOf(DialResult.Connected(session, peer)))
        val harness = Harness(this, dialer, features, directory)
        harness.orchestrator.start()
        runCurrent()

        harness.orchestrator.stop()
        runCurrent()

        assertEquals(1, features[0].detached)
        assertNull(harness.registry.current.value)
        assertTrue(session.state.value is ConnectionState.Disconnected)
        harness.orchestrator.close()
    }

    @Test
    fun tandemServiceComposition_pinMismatch_nothingRegisteredOrAttachedAndFailureVisible(
        @TempDir directory: File,
    ) = runTest {
        val failure = ConnectionFailure.HandshakeError("PIN_MISMATCH")
        val features = listOf(CountingFeature())
        val dialer = ScriptedDialer(mutableListOf(DialResult.PinMismatch(failure)))
        val harness = Harness(this, dialer, features, directory)

        harness.orchestrator.start()
        runCurrent()

        assertNull(harness.registry.current.value)
        assertEquals(0, features[0].attached)
        assertEquals(failure, harness.orchestrator.failure.value)
        assertTrue(!harness.knownPeers.hasEverPinned(peer))
        harness.orchestrator.close()
    }

    @Test
    fun tandemServiceComposition_sessionFailsBeforeReady_notRegistered(
        @TempDir directory: File,
    ) = runTest {
        val failing = FakeTandemSession().apply { emitState(ConnectionState.Failed(ConnectionFailure.Timeout)) }
        val features = listOf(CountingFeature())
        val dialer = ScriptedDialer(mutableListOf(DialResult.Connected(failing, peer)))
        val harness = Harness(this, dialer, features, directory)

        harness.orchestrator.start()
        runCurrent()

        assertNull(harness.registry.current.value)
        assertEquals(0, features[0].attached)
        assertEquals(ConnectionFailure.Timeout, harness.orchestrator.failure.value)
        harness.orchestrator.close()
    }

    @Test
    fun orchestrator_sessionClosedRightAfterReady_noCrashNothingRegistered(
        @TempDir directory: File,
    ) = runTest {
        val closing = readySession()
        val features = listOf(CountingFeature())
        val dialer =
            object : SessionDialer {
                override suspend fun dial(candidate: CandidateAddress): DialResult {
                    closing.close()
                    return DialResult.Connected(closing, peer)
                }
            }
        val harness = Harness(this, dialer, features, directory)

        harness.orchestrator.start()
        runCurrent()

        assertNull(harness.registry.current.value)
        assertEquals(0, features[0].attached)
        harness.orchestrator.close()
    }

    @Test
    fun orchestrator_dialerThrowsNonIoException_failureVisibleLoopSurvives(
        @TempDir directory: File,
    ) = runTest {
        val features = listOf(CountingFeature())
        val dialer =
            object : SessionDialer {
                override suspend fun dial(candidate: CandidateAddress): DialResult = error("identity lost")
            }
        val harness = Harness(this, dialer, features, directory)

        harness.orchestrator.start()
        runCurrent()

        assertNull(harness.registry.current.value)
        assertEquals(ConnectionFailure.HandshakeError("HANDSHAKE_FAILED"), harness.orchestrator.failure.value)
        harness.orchestrator.close()
    }

    @Test
    fun orchestrator_stoppedWhileSettling_sessionClosedNotAttached(
        @TempDir directory: File,
    ) = runTest {
        val settling = FakeTandemSession().apply { emitState(ConnectionState.Connecting) }
        val features = listOf(CountingFeature())
        val dialer = ScriptedDialer(mutableListOf(DialResult.Connected(settling, peer)))
        val harness = Harness(this, dialer, features, directory)
        harness.orchestrator.start()
        runCurrent()

        harness.orchestrator.stop()
        runCurrent()

        assertTrue(settling.state.value is ConnectionState.Disconnected)
        assertNull(harness.registry.current.value)
        assertEquals(0, features[0].attached)
        harness.orchestrator.close()
    }

    @Test
    fun orchestrator_stopRacingSessionClose_noRestart(
        @TempDir directory: File,
    ) = runTest {
        val first = readySession()
        val features = listOf(CountingFeature())
        val dialer = ScriptedDialer(mutableListOf(DialResult.Connected(first, peer)))
        val harness = Harness(this, dialer, features, directory)
        harness.orchestrator.start()
        runCurrent()
        val dialsBefore = dialer.dials

        first.close()
        harness.orchestrator.stop()
        runCurrent()

        assertEquals(dialsBefore, dialer.dials)
        assertNull(harness.registry.current.value)
        harness.orchestrator.close()
    }

    @Test
    fun orchestrator_screenOnAfterDeadPeer_dialsAtZeroVirtualTime(
        @TempDir directory: File,
    ) = runTest {
        val dialer =
            ScriptedDialer(mutableListOf(DialResult.Unreachable(null), DialResult.Connected(readySession(), peer)))
        val harness = Harness(this, dialer, listOf(CountingFeature()), directory)
        harness.orchestrator.start()
        runCurrent()
        assertEquals(1, dialer.dials)

        advanceTimeBy(200)
        val wokeAt = testScheduler.currentTime
        harness.screenOn.tryEmit(Unit)
        runCurrent()

        assertEquals(2, dialer.dials)
        assertEquals(wokeAt, testScheduler.currentTime)
        harness.orchestrator.close()
    }
}
