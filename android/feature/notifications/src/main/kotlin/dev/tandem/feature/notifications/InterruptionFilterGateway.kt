package dev.tandem.feature.notifications

import android.app.NotificationManager
import android.content.Context

/** This device's Do Not Disturb interruption filter (`NotificationManager`'s own enum). */
enum class InterruptionFilter {
    ALL,
    PRIORITY,
    NONE,
    ALARMS,
    UNKNOWN,
}

/**
 * Seam over `NotificationManager`'s interruption filter and notification-policy access (E72-04,
 * F-10.2), so [FocusSyncReceiver] stays plain unit-tested against a fake (CLAUDE.md's Robolectric
 * rule). [SystemInterruptionFilterGateway] is the only production implementation.
 */
interface InterruptionFilterGateway {
    fun hasPolicyAccess(): Boolean

    fun currentFilter(): InterruptionFilter

    fun setFilter(filter: InterruptionFilter)
}

/** Production implementation backed by the real `NotificationManager`. */
class SystemInterruptionFilterGateway(
    context: Context,
) : InterruptionFilterGateway {
    private val notificationManager = context.getSystemService(NotificationManager::class.java)

    override fun hasPolicyAccess(): Boolean = notificationManager.isNotificationPolicyAccessGranted

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
