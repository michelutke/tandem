package dev.tandem.app.connection

import dev.tandem.app.service.SessionRegistry
import dev.tandem.core.protocol.connection.ConnectionFailure
import dev.tandem.core.protocol.connection.ConnectionState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn

/**
 * The connection state [ConnectionStatusViewModel] shows (E20-24): the registered Ready session's
 * state, [ConnectionState.Disconnected] while none is registered, and [ConnectionState.Failed]
 * whenever the orchestrator holds a sanitized [failure] (invariant 5: pin mismatch stays visible).
 */
@OptIn(ExperimentalCoroutinesApi::class)
fun orchestratorConnectionState(
    registry: SessionRegistry,
    failure: StateFlow<ConnectionFailure?>,
    scope: CoroutineScope,
): StateFlow<ConnectionState> =
    combine(
        registry.current.flatMapLatest { it?.session?.state ?: flowOf(ConnectionState.Disconnected()) },
        failure,
    ) { sessionState, currentFailure ->
        if (currentFailure != null) ConnectionState.Failed(currentFailure) else sessionState
    }.stateIn(scope, SharingStarted.Eagerly, ConnectionState.Disconnected())
