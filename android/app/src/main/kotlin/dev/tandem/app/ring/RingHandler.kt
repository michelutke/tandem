package dev.tandem.app.ring

import android.annotation.SuppressLint
import android.content.Context
import androidx.core.content.edit

/**
 * Handles the STATUS-channel Ring/RingStop flow on the phone side (E23-05, F-4.4, UC-06): [ring]
 * is called when `Ring` is received, [stop] when `RingStop` is received (or the phone dismisses
 * the alarm itself, E23-06). Always starts the looping alarm-usage playback at max `STREAM_ALARM`
 * volume, and additionally switches the interruption filter from total silence (`NONE`) to
 * `ALARMS` when Tandem holds notification policy access, restoring both on [stop].
 *
 * Framework-free: reads [alarmPlayer] and [notificationPolicyAccess] instead of
 * `AudioManager`/`MediaPlayer`/`NotificationManager` directly, so it stays plain unit-tested
 * against fakes (CLAUDE.md's Robolectric rule).
 */
class RingHandler(
    private val alarmPlayer: AlarmPlayer,
    private val notificationPolicyAccess: NotificationPolicyAccess,
    private val filterSwitchRecord: RingFilterSwitchRecord = InMemoryRingFilterSwitchRecord(),
) {
    /**
     * True once [ring] has run without notification policy access -- the caller shows
     * [RingPolicyExplanationScreen] before the user can open the policy access settings screen.
     */
    var needsPolicyExplanation: Boolean = false
        private set

    fun ring() {
        needsPolicyExplanation = !notificationPolicyAccess.hasAccess()
        if (!needsPolicyExplanation && notificationPolicyAccess.currentFilter() == InterruptionFilter.NONE) {
            notificationPolicyAccess.setFilter(InterruptionFilter.ALARMS)
            filterSwitchRecord.set()
        }
        alarmPlayer.start()
    }

    /** Puts back total silence if a ring that a process death cut short had switched it to alarms only. */
    fun restoreStaleFilter() {
        if (!filterSwitchRecord.isSet()) return
        val stillAlarms =
            notificationPolicyAccess.hasAccess() &&
                notificationPolicyAccess.currentFilter() == InterruptionFilter.ALARMS
        if (stillAlarms) notificationPolicyAccess.setFilter(InterruptionFilter.NONE)
        filterSwitchRecord.clear()
    }

    fun stop() {
        alarmPlayer.stop()
        if (filterSwitchRecord.isSet()) {
            notificationPolicyAccess.setFilter(InterruptionFilter.NONE)
            filterSwitchRecord.clear()
        }
    }
}

/** Remembers that [RingHandler] switched total silence to alarms only, so a process death cannot lose it. */
interface RingFilterSwitchRecord {
    fun isSet(): Boolean

    fun set()

    fun clear()
}

class InMemoryRingFilterSwitchRecord : RingFilterSwitchRecord {
    private var switched = false

    override fun isSet(): Boolean = switched

    override fun set() {
        switched = true
    }

    override fun clear() {
        switched = false
    }
}

/** [RingFilterSwitchRecord] that survives process death; writes are synchronous so a kill cannot lose them. */
@SuppressLint("ApplySharedPref")
class SharedPreferencesRingFilterSwitchRecord(
    context: Context,
) : RingFilterSwitchRecord {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    override fun isSet(): Boolean = preferences.getBoolean(KEY_SWITCHED, false)

    override fun set() {
        preferences.edit(commit = true) { putBoolean(KEY_SWITCHED, true) }
    }

    override fun clear() {
        preferences.edit(commit = true) { remove(KEY_SWITCHED) }
    }

    private companion object {
        const val PREFERENCES_NAME = "ring_filter_switch"
        const val KEY_SWITCHED = "switched_to_alarms"
    }
}
