package dev.tandem.app.home

import dev.tandem.app.connection.ConnectionErrorMapper
import dev.tandem.core.protocol.connection.ConnectionFailure
import dev.tandem.core.protocol.connection.ConnectionState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map

/**
 * Home screen view model (E20-17; ui-spec.md §6, §7.2). Combines [ringStateSource]'s task/idle
 * state with [connectionState] and [macName] into the ring content, the TitleBlock status line,
 * and whether a trust failure should replace the whole screen with the Blocked. screen
 * (invariant 5, CLAUDE.md; E12-16).
 *
 * The Blocked. trigger matches [dev.tandem.app.connection.ConnectionErrorMapper]'s own PIN_MISMATCH
 * / REVOKED cases exactly -- version mismatch and plain network/timeout failures keep the ordinary
 * status line rather than replacing Home (ui-spec §8's "Version mismatch" row is a distinct
 * "Update needed." variant, not built by this issue).
 */
class HomeViewModel(
    ringStateSource: HomeRingStateSource,
    connectionState: StateFlow<ConnectionState>,
    failedCycles: StateFlow<Int>,
    macName: StateFlow<String?>,
) {
    val ringState: StateFlow<HomeRingState> = ringStateSource.state

    /** [dev.tandem.core.designsystem.components.TitleBlock]'s state line while not blocked. */
    val statusLine: Flow<String> = combine(connectionState, failedCycles, macName, ::toStatusLine)

    /** True once a trust failure must replace Home with the Blocked. screen. */
    val isBlocked: Flow<Boolean> = connectionState.map(::isTrustFailure)

    /** The Blocked. screen's explanation line, valid only while [isBlocked] is true. */
    val blockedMessage: Flow<String> =
        combine(connectionState, macName) { state, name ->
            if (state is ConnectionState.Failed) {
                ConnectionErrorMapper.mapToErrorMessage(state.reason, name)
            } else {
                ""
            }
        }

    private fun toStatusLine(
        state: ConnectionState,
        @Suppress("UNUSED_PARAMETER") unreachableCycles: Int,
        macName: String?,
    ): String =
        when (state) {
            is ConnectionState.Ready -> "Linked to ${macName ?: "your Mac"}."

            ConnectionState.Connecting, ConnectionState.TlsHandshaking, ConnectionState.HelloExchange,
            is ConnectionState.Disconnected,
            -> "Reconnecting…"

            is ConnectionState.Failed -> "" // Home is replaced by the Blocked. screen instead.
        }

    companion object {
        /** Matches [ConnectionErrorMapper]'s own PIN_MISMATCH / REVOKED cases exactly (invariant 5). */
        internal fun isTrustFailure(state: ConnectionState): Boolean {
            val reason = (state as? ConnectionState.Failed)?.reason as? ConnectionFailure.HandshakeError
            return reason != null && (reason.message.contains("PIN_MISMATCH") || reason.message.contains("REVOKED"))
        }
    }
}
