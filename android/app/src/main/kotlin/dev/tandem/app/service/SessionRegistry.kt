package dev.tandem.app.service

import dev.tandem.core.crypto.SpkiFingerprint
import dev.tandem.core.transport.TandemSession
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class RegisteredSession(
    val session: TandemSession,
    val peer: SpkiFingerprint,
)

/**
 * Process-wide slot for the one live control session (E20-21). Whoever dials or accepts a session
 * (E20-05+) registers it here; [TandemService] consumes its CONTROL channel for `Revoke`.
 */
class SessionRegistry {
    private val mutableCurrent = MutableStateFlow<RegisteredSession?>(null)
    val current: StateFlow<RegisteredSession?> = mutableCurrent.asStateFlow()

    fun register(
        session: TandemSession,
        peer: SpkiFingerprint,
    ) {
        mutableCurrent.value = RegisteredSession(session, peer)
    }

    fun clear(session: TandemSession) {
        mutableCurrent.value = mutableCurrent.value?.takeIf { it.session !== session }
    }
}
