package dev.tandem.app.home

import dev.tandem.app.connection.ConnectionErrorMapper
import dev.tandem.core.protocol.connection.ConnectionFailure
import dev.tandem.core.protocol.connection.ConnectionState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map

/** Why a trust failure replaces Home with the Blocked. screen (ui-spec §7.2, §8). */
enum class BlockedReason { PinMismatch, Revoked, UpdateNeeded }

/**
 * Home screen view model (E20-17; ui-spec.md §6, §7.2). Combines [ringStateSource]'s task/idle
 * state with [connectionState] and [macName] into the ring content, the TitleBlock status line,
 * and whether a trust failure should replace the whole screen with the Blocked. screen
 * (invariant 5, CLAUDE.md; E12-16). The status line also carries the non-trust error states: the
 * identity-reset notice while [rePairNeeded], an unavailable identity, a handshake timeout and, after
 * [UNREACHABLE_CYCLE_THRESHOLD] failed cycles, the same-Wi-Fi hint. Other failures keep Home and show
 * "Reconnecting…" because the connection loop keeps retrying.
 */
class HomeViewModel(
    ringStateSource: HomeRingStateSource,
    connectionState: StateFlow<ConnectionState>,
    macName: StateFlow<String?>,
    failedCycles: StateFlow<Int> = MutableStateFlow(0),
    rePairNeeded: StateFlow<Boolean> = MutableStateFlow(false),
) {
    val ringState: StateFlow<HomeRingState> = ringStateSource.state

    /** [dev.tandem.core.designsystem.components.TitleBlock]'s state line while not blocked. */
    val statusLine: Flow<String> =
        combine(connectionState, macName, ringStateSource.state, failedCycles, rePairNeeded, ::toStatusLine)

    /** The trust failure that must replace Home with the Blocked. screen, or null. */
    val blocked: Flow<BlockedReason?> = connectionState.map(::blockedReason)

    /** True once a trust failure must replace Home with the Blocked. screen. */
    val isBlocked: Flow<Boolean> = blocked.map { it != null }

    private fun toStatusLine(
        state: ConnectionState,
        macName: String?,
        ring: HomeRingState,
        unreachableCycles: Int,
        rePairNeeded: Boolean,
    ): String =
        when {
            rePairNeeded -> {
                errorLine(ConnectionErrorMapper.identityResetMessage(macName))
            }

            state is ConnectionState.Ready -> {
                readyLine(macName, ring)
            }

            state is ConnectionState.Failed -> {
                failedLine(state.reason)
            }

            state is ConnectionState.Disconnected && unreachableCycles >= UNREACHABLE_CYCLE_THRESHOLD -> {
                NETWORK_ISOLATION_HINT
            }

            else -> {
                RECONNECTING_LINE
            }
        }

    private fun failedLine(reason: ConnectionFailure): String =
        when (reason) {
            ConnectionFailure.Timeout, ConnectionFailure.IdentityUnavailable -> {
                errorLine(ConnectionErrorMapper.mapToErrorMessage(reason))
            }

            else -> {
                RECONNECTING_LINE
            }
        }

    private fun errorLine(message: String): String = "Error: $message"

    private fun readyLine(
        macName: String?,
        ring: HomeRingState,
    ): String =
        when (ring) {
            is HomeRingState.Transfer -> if (ring.toMac) SENDING_LINE else RECEIVING_LINE
            else -> "Linked to ${macName ?: "your Mac"}."
        }

    companion object {
        internal const val RECONNECTING_LINE = "Reconnecting…"
        internal const val SENDING_LINE = "Sending to Mac."
        internal const val RECEIVING_LINE = "Receiving from Mac."
        internal const val UNREACHABLE_CYCLE_THRESHOLD = 3
        internal const val NETWORK_ISOLATION_HINT =
            "Can't reach your Mac. Make sure both devices are on the same Wi-Fi. Guest networks and " +
                "hotspots often block devices from reaching each other."

        /** Pin mismatch and revoked block Home; a version mismatch needs an update (invariant 5). */
        internal fun blockedReason(state: ConnectionState): BlockedReason? {
            val reason = (state as? ConnectionState.Failed)?.reason
            return when {
                reason == ConnectionFailure.VersionMismatch -> BlockedReason.UpdateNeeded
                reason !is ConnectionFailure.HandshakeError -> null
                reason.message.contains("PIN_MISMATCH") -> BlockedReason.PinMismatch
                reason.message.contains("REVOKED") -> BlockedReason.Revoked
                else -> null
            }
        }
    }
}
