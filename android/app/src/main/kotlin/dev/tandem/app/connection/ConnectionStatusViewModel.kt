package dev.tandem.app.connection

import dev.tandem.core.protocol.connection.ConnectionState

/**
 * View model for connection status display (E12-16).
 */
class ConnectionStatusViewModel {
    fun getStatusText(state: ConnectionState): String =
        when (state) {
            is ConnectionState.Failed -> {
                ConnectionErrorMapper.mapToErrorMessage(state.reason)
            }

            ConnectionState.Connecting -> {
                "Connecting..."
            }

            ConnectionState.TlsHandshaking -> {
                "Securing connection..."
            }

            ConnectionState.HelloExchange -> {
                "Negotiating..."
            }

            is ConnectionState.Ready -> {
                "Connected"
            }

            is ConnectionState.Disconnected -> {
                state.reason ?: "Disconnected"
            }
        }
}
