package dev.tandem.app.connection

import dev.tandem.core.pairing.rotation.HandshakeResult
import dev.tandem.core.pairing.rotation.PendingRotationHandshake
import dev.tandem.core.protocol.connection.ConnectionState
import dev.tandem.core.transport.reconnect.CandidateAddress
import kotlinx.coroutines.flow.first

/**
 * Puts [PendingRotationHandshake] in the dial path (E70-15, E70-08): a handshake the Mac rejects is
 * retried once with the pending rotation key, and only a session that reaches Ready commits it.
 * [dialerFor] dials with the key stored under the given alias. A session that does not settle
 * Ready is closed and read as a rejection.
 */
class PendingRotationSessionDialer(
    private val handshake: PendingRotationHandshake,
    private val dialerFor: (alias: String) -> SessionDialer,
    private val onAuthenticated: () -> Unit = {},
) : SessionDialer {
    override suspend fun dial(candidate: CandidateAddress): DialResult {
        var last: DialResult = DialResult.Unreachable(null)
        val authenticated =
            handshake.connect { alias ->
                val result = dialerFor(alias).dial(candidate)
                last = result
                when (result) {
                    is DialResult.Connected -> {
                        val (handshakeResult, settled) = settle(result)
                        last = settled
                        handshakeResult
                    }

                    is DialResult.PinMismatch -> {
                        HandshakeResult.NetworkError
                    }

                    is DialResult.Unreachable -> {
                        if (result.failure == null) HandshakeResult.NetworkError else HandshakeResult.Rejected
                    }
                }
            }
        if (authenticated) onAuthenticated()
        return last
    }

    private suspend fun settle(dialed: DialResult.Connected): Pair<HandshakeResult, DialResult> {
        val settled =
            dialed.session.state.first {
                it is ConnectionState.Ready || it is ConnectionState.Disconnected || it is ConnectionState.Failed
            }
        if (settled is ConnectionState.Ready) return HandshakeResult.Accepted(authenticated = true) to dialed
        dialed.session.close()
        return HandshakeResult.Rejected to DialResult.Unreachable((settled as? ConnectionState.Failed)?.reason)
    }
}
