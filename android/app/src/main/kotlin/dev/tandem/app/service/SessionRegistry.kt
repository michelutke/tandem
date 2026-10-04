package dev.tandem.app.service

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.TandemSession
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

data class RegisteredSession(
    val session: TandemSession,
    val peer: SpkiFingerprint,
)

/**
 * Process-wide slot for the one live control session (E20-21). Whoever dials or accepts a session
 * (E20-05+) registers it here; [TandemService] consumes its CONTROL channel for `Revoke`. Nothing
 * produces sessions yet: the dialer that calls [register] arrives with E20-05, so this wiring is
 * dormant until then.
 */
class SessionRegistry {
    private val mutableCurrent = MutableStateFlow<RegisteredSession?>(null)
    val current: StateFlow<RegisteredSession?> = mutableCurrent.asStateFlow()

    /**
     * Only for a [session] that is already Ready; CONTROL is fanned out per subscriber (E20-22),
     * so other CONTROL collectors on it do not compete with the Revoke consumer. That consumer
     * subscribes asynchronously after [current] changes, so a CONTROL frame delivered in the window
     * between this call and its subscription is not replayed to it (a late subscriber sees only
     * frames delivered after it registers).
     */
    fun register(
        session: TandemSession,
        peer: SpkiFingerprint,
    ) {
        require(session.state.value is ConnectionState.Ready) { "Only a Ready session may be registered" }
        mutableCurrent.value = RegisteredSession(session, peer)
    }

    fun clear(session: TandemSession) {
        mutableCurrent.update { current -> current?.takeIf { it.session !== session } }
    }
}
