package dev.tandem.feature.notifications

import android.annotation.SuppressLint
import android.content.Context
import androidx.core.content.edit
import dev.tandem.core.transport.TandemSession
import dev.tandem.core.transport.sendOrDrop
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
    private val record: FocusFilterRecord,
) {
    /**
     * Collects [session]'s CONTROL frames and applies each `FocusState` until cancelled. The filter
     * recorded before priority-only was applied is persisted in [record], and restored when the
     * session ends (the Mac may disappear while Focus is on) or, after a process death, on the next
     * start.
     */
    suspend fun run() {
        restoreRecordedFocusFilter(record, gateway)
        try {
            session
                .receive(Channel.CHANNEL_CONTROL)
                .filter { it.hasFocusState() }
                .collect { applyFocus(it.focusState.on) }
        } finally {
            restoreRecordedFocusFilter(record, gateway)
        }
    }

    private suspend fun applyFocus(on: Boolean) {
        if (!gateway.hasPolicyAccess()) {
            session.sendOrDrop(Channel.CHANNEL_CONTROL) {
                focusSyncCapability = focusSyncCapability { available = false }
            }
            return
        }
        if (on) {
            if (record.load() == null) record.save(gateway.currentFilter())
            gateway.setFilter(InterruptionFilter.PRIORITY)
        } else {
            restoreRecordedFocusFilter(record, gateway)
        }
    }
}

/** Where [FocusSyncReceiver] keeps the filter that was active before it applied priority-only. */
interface FocusFilterRecord {
    fun load(): InterruptionFilter?

    fun save(filter: InterruptionFilter)

    fun clear()
}

/** [FocusFilterRecord] that survives process death; writes are synchronous so a kill right after cannot lose them. */
@SuppressLint("ApplySharedPref")
class SharedPreferencesFocusFilterRecord(
    context: Context,
) : FocusFilterRecord {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    override fun load(): InterruptionFilter? =
        preferences.getString(KEY_FILTER, null)?.let { name ->
            InterruptionFilter.entries.firstOrNull { it.name == name }
        }

    override fun save(filter: InterruptionFilter) {
        preferences.edit(commit = true) { putString(KEY_FILTER, filter.name) }
    }

    override fun clear() {
        preferences.edit(commit = true) { remove(KEY_FILTER) }
    }

    private companion object {
        const val PREFERENCES_NAME = "focus_sync"
        const val KEY_FILTER = "filter_before_sync"
    }
}

/** Puts back the filter recorded before a Focus sync, if any, and forgets it. */
fun restoreRecordedFocusFilter(
    record: FocusFilterRecord,
    gateway: InterruptionFilterGateway,
) {
    val recorded = record.load() ?: return
    if (gateway.hasPolicyAccess()) gateway.setFilter(recorded)
    record.clear()
}
