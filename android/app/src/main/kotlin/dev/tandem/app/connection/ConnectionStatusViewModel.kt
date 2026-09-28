package dev.tandem.app.connection

import dev.tandem.core.protocol.connection.ConnectionState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine

private const val UNREACHABLE_CYCLE_THRESHOLD = 3

private const val NETWORK_ISOLATION_HINT =
    "Can't reach your Mac. Make sure both devices are on the same Wi-Fi. Guest networks and " +
        "hotspots often block devices from reaching each other."

/**
 * Connection-status view model (E20-09; invariant 5, CLAUDE.md -- the pin-mismatch [ConnectionState.Failed]
 * case this combines is the phone's only visible fail-closed surface). Combines the E12-08
 * [ConnectionStateMachine][dev.tandem.core.protocol.connection.ConnectionStateMachine]'s
 * [connectionState], the E20-06 `ReconnectStrategy.failedCycles` and the paired Mac's display name
 * into one user-visible status label, updated live as any of the three change.
 */
class ConnectionStatusViewModel(
    connectionState: StateFlow<ConnectionState>,
    failedCycles: StateFlow<Int>,
    macName: StateFlow<String?>,
) {
    /** The label [ConnectionStatusScreen] renders; see this class's kdoc for the exact strings. */
    val statusText: Flow<String> =
        combine(connectionState, failedCycles, macName, ::toStatusText)

    private fun toStatusText(
        state: ConnectionState,
        unreachableCycles: Int,
        macName: String?,
    ): String =
        when (state) {
            is ConnectionState.Ready -> {
                "Connected to ${macName ?: "your Mac"}"
            }

            ConnectionState.Connecting, ConnectionState.TlsHandshaking, ConnectionState.HelloExchange -> {
                if (unreachableCycles > 0) "Reconnecting…" else "Connecting…"
            }

            is ConnectionState.Disconnected -> {
                if (unreachableCycles >= UNREACHABLE_CYCLE_THRESHOLD) {
                    NETWORK_ISOLATION_HINT
                } else {
                    "Disconnected"
                }
            }

            is ConnectionState.Failed -> {
                "Error: ${ConnectionErrorMapper.mapToErrorMessage(state.reason, macName)}"
            }
        }
}
