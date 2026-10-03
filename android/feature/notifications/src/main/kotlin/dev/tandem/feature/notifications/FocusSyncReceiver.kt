package dev.tandem.feature.notifications

import dev.tandem.core.transport.TandemSession
import dev.tandem.protocol.v1.Channel
import dev.tandem.protocol.v1.focusSyncCapability
import kotlinx.coroutines.flow.filter

/**
 * E72-04 (F-10.2, docs/protocol/SPEC.md #focus-sync): applies the Mac's `FocusState` to this
 * device's interruption filter through [gateway]. Focus on records the current filter (once) and
 * sets priority-only; focus off restores the recorded filter. Without notification-policy access
 * the filter is never touched and the Mac is answered `FocusSyncCapability { available: false }`.
 */
class FocusSyncReceiver(
    private val session: TandemSession,
    private val gateway: InterruptionFilterGateway,
) {
    private var filterBeforeSync: InterruptionFilter? = null

    /** Collects [session]'s CONTROL frames and applies each `FocusState` until cancelled. */
    suspend fun run() {
        session
            .receive(Channel.CHANNEL_CONTROL)
            .filter { it.hasFocusState() }
            .collect { applyFocus(it.focusState.on) }
    }

    private suspend fun applyFocus(on: Boolean) {
        if (!gateway.hasPolicyAccess()) {
            session.send(Channel.CHANNEL_CONTROL) {
                focusSyncCapability = focusSyncCapability { available = false }
            }
            return
        }
        if (on) {
            if (filterBeforeSync == null) filterBeforeSync = gateway.currentFilter()
            gateway.setFilter(InterruptionFilter.PRIORITY)
        } else {
            filterBeforeSync?.let(gateway::setFilter)
            filterBeforeSync = null
        }
    }
}
