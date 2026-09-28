package dev.tandem.app.ring

import android.app.NotificationManager
import android.content.Context

/** This device's current Do Not Disturb interruption filter (`NotificationManager`'s own enum). */
enum class InterruptionFilter {
    ALL,
    PRIORITY,
    NONE,
    ALARMS,
    UNKNOWN,
}

/**
 * Seam over `NotificationManager`'s notification policy access (E23-05, F-4.4, UC-06): whether
 * Tandem holds `ACCESS_NOTIFICATION_POLICY` access, the device's current interruption filter, and
 * setting it -- so [RingHandler] stays plain unit-tested against a fake (CLAUDE.md's Robolectric
 * rule) instead of touching the framework directly. [SystemNotificationPolicyAccess] is the only
 * production implementation.
 */
interface NotificationPolicyAccess {
    fun hasAccess(): Boolean

    fun currentFilter(): InterruptionFilter

    fun setFilter(filter: InterruptionFilter)
}

/** Production implementation backed by the real `NotificationManager`. */
class SystemNotificationPolicyAccess(
    context: Context,
) : NotificationPolicyAccess {
    private val notificationManager = context.getSystemService(NotificationManager::class.java)

    override fun hasAccess(): Boolean = notificationManager.isNotificationPolicyAccessGranted

    override fun currentFilter(): InterruptionFilter =
        when (notificationManager.currentInterruptionFilter) {
            NotificationManager.INTERRUPTION_FILTER_ALL -> InterruptionFilter.ALL
            NotificationManager.INTERRUPTION_FILTER_PRIORITY -> InterruptionFilter.PRIORITY
            NotificationManager.INTERRUPTION_FILTER_NONE -> InterruptionFilter.NONE
            NotificationManager.INTERRUPTION_FILTER_ALARMS -> InterruptionFilter.ALARMS
            else -> InterruptionFilter.UNKNOWN
        }

    override fun setFilter(filter: InterruptionFilter) {
        val interruptionFilter =
            when (filter) {
                InterruptionFilter.ALL -> NotificationManager.INTERRUPTION_FILTER_ALL
                InterruptionFilter.PRIORITY -> NotificationManager.INTERRUPTION_FILTER_PRIORITY
                InterruptionFilter.NONE -> NotificationManager.INTERRUPTION_FILTER_NONE
                InterruptionFilter.ALARMS -> NotificationManager.INTERRUPTION_FILTER_ALARMS
                InterruptionFilter.UNKNOWN -> return
            }
        notificationManager.setInterruptionFilter(interruptionFilter)
    }
}
