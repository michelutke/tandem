package dev.tandem.app.connection

import dev.tandem.app.service.RegisteredSession
import dev.tandem.app.service.SessionRegistry
import dev.tandem.core.protocol.connection.ConnectionFailure
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.heartbeat.DeviceIdleSource
import dev.tandem.core.transport.reconnect.CandidateAddress
import dev.tandem.core.transport.reconnect.ConnectResult
import dev.tandem.core.transport.reconnect.Connector
import dev.tandem.core.transport.reconnect.NetworkMonitor
import dev.tandem.core.transport.reconnect.NetworkReconnectTrigger
import dev.tandem.core.transport.reconnect.PairedMacBonjourSource
import dev.tandem.core.transport.reconnect.PairingAddressSource
import dev.tandem.core.transport.reconnect.ReconnectStrategy
import dev.tandem.core.transport.reconnect.WakeReconnectTrigger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.io.IOException
import java.time.Clock

/**
 * The production connect loop (E20-23, F-3.4): [ReconnectStrategy] walks candidate addresses,
 * [dialer] opens a pinned mTLS session, and the first one to reach Ready is recorded in
 * [knownPeerStore], registered in [registry] and handed to [featureAttacher]. When it closes,
 * every consumer detaches (the attacher returns only after that) and the loop starts again, so a
 * reconnect re-attaches exactly once. A network-available event ([NetworkReconnectTrigger]) or a
 * wake, Doze exit or app foregrounding ([WakeReconnectTrigger]) kicks the loop.
 *
 * [failure] carries only sanitized categories (`PIN_MISMATCH`, `REVOKED`, `HANDSHAKE_FAILED`,
 * handshake timeout) for a visible error (invariant 5); it clears on the next Ready session.
 */
@Suppress("LongParameterList") // composition seams: dialer, stores, sources, features, clock, dispatcher
class ConnectionOrchestrator(
    private val dialer: SessionDialer,
    private val registry: SessionRegistry,
    private val featureAttacher: FeatureAttacher,
    private val knownPeerStore: KnownPeerStore,
    private val bonjourSource: PairedMacBonjourSource,
    pairingAddressSource: PairingAddressSource,
    networkMonitor: NetworkMonitor,
    deviceIdleSource: DeviceIdleSource,
    foreground: Flow<Unit>,
    clock: Clock,
    dispatcher: CoroutineDispatcher,
    private val warn: (String) -> Unit = {},
) : ConnectionLoop {
    private val scope =
        CoroutineScope(SupervisorJob() + dispatcher)
    private val lock = Any()
    private var runJob: Job? = null
    private var sessionJob: Job? = null

    private val strategy =
        ReconnectStrategy(
            connector = Connector { candidate -> connect(candidate) },
            bonjourSource = bonjourSource,
            pairingAddressSource = pairingAddressSource,
            dispatcher = dispatcher,
        )
    private val networkTrigger = NetworkReconnectTrigger(networkMonitor, strategy, clock, dispatcher)
    private val wakeTrigger = WakeReconnectTrigger(deviceIdleSource, strategy, clock, dispatcher, foreground)

    private val mutableFailure = MutableStateFlow<ConnectionFailure?>(null)
    val failure: StateFlow<ConnectionFailure?> = mutableFailure.asStateFlow()
    val failedCycles: StateFlow<Int> = strategy.failedCycles

    override fun start() {
        synchronized(lock) { runJob = runJob?.takeIf { it.isActive } ?: Job(scope.coroutineContext[Job]) }
        bonjourSource.start()
        networkTrigger.start()
        wakeTrigger.start()
        synchronized(lock) { strategy.start() }
    }

    override fun stop() {
        synchronized(lock) {
            runJob?.cancel()
            runJob = null
            sessionJob = null
        }
        networkTrigger.stop()
        wakeTrigger.stop()
        strategy.stop()
        registry.current.value?.let { current ->
            registry.clear(current.session)
            current.session.close()
        }
    }

    fun close() {
        stop()
        bonjourSource.close()
        networkTrigger.close()
        wakeTrigger.close()
        strategy.close()
        scope.cancel()
    }

    private suspend fun connect(candidate: CandidateAddress): ConnectResult =
        try {
            dialAndAdopt(candidate)
        } catch (e: CancellationException) {
            throw e
        } catch (
            @Suppress("TooGenericExceptionCaught", "SwallowedException") e: Exception,
        ) {
            mutableFailure.value = HANDSHAKE_FAILURE
            ConnectResult.Unreachable
        }

    private suspend fun dialAndAdopt(candidate: CandidateAddress): ConnectResult =
        when (val result = dialer.dial(candidate)) {
            is DialResult.Connected -> {
                adopt(result)
            }

            is DialResult.PinMismatch -> {
                mutableFailure.value = result.failure
                ConnectResult.PinMismatch
            }

            is DialResult.Unreachable -> {
                result.failure?.let { mutableFailure.value = it }
                ConnectResult.Unreachable
            }
        }

    private suspend fun adopt(dialed: DialResult.Connected): ConnectResult {
        val session = dialed.session
        return try {
            settleAndRegister(dialed)
        } catch (e: CancellationException) {
            session.close()
            throw e
        } catch (
            @Suppress("TooGenericExceptionCaught") e: Exception,
        ) {
            registry.clear(session)
            session.close()
            throw e
        }
    }

    private suspend fun settleAndRegister(dialed: DialResult.Connected): ConnectResult {
        val session = dialed.session
        val settled =
            session.state.first {
                it is ConnectionState.Ready || it is ConnectionState.Disconnected || it is ConnectionState.Failed
            }
        if (settled !is ConnectionState.Ready) {
            session.close()
            (settled as? ConnectionState.Failed)?.let { mutableFailure.value = it.reason }
            return ConnectResult.Unreachable
        }
        recordKnownPeer(dialed)
        val registered = synchronized(lock) { registerIfRunning(dialed) }
        if (!registered) session.close()
        return if (registered) ConnectResult.Connected else ConnectResult.Unreachable
    }

    private fun recordKnownPeer(dialed: DialResult.Connected) {
        try {
            knownPeerStore.recordPinned(dialed.peer)
        } catch (
            @Suppress("SwallowedException") e: IOException,
        ) {
            warn("known-peer persistence failed: ${e.javaClass.simpleName}")
        }
    }

    private fun registerIfRunning(dialed: DialResult.Connected): Boolean {
        val run = runJob?.takeIf { it.isActive } ?: return false
        registry.register(dialed.session, dialed.peer, dialed.address)
        mutableFailure.value = null
        val registered = RegisteredSession(dialed.session, dialed.peer, dialed.peerSpkiDer)
        sessionJob = scope.launch(run) { runSession(registered, run) }
        return true
    }

    private suspend fun runSession(
        registered: RegisteredSession,
        run: Job,
    ) {
        try {
            featureAttacher.attach(registered)
        } finally {
            registry.clear(registered.session)
        }
        synchronized(lock) { if (run.isActive) strategy.start() }
    }

    private companion object {
        val HANDSHAKE_FAILURE = ConnectionFailure.HandshakeError("HANDSHAKE_FAILED")
    }
}
