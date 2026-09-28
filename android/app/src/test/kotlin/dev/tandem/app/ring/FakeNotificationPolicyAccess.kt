package dev.tandem.app.ring

/**
 * Recording fake for [NotificationPolicyAccess] (E23-05): models access and the current
 * interruption filter as plain state instead of touching `NotificationManager`, so [RingHandler]
 * stays plain unit-tested (CLAUDE.md's Robolectric rule).
 */
class FakeNotificationPolicyAccess(
    private val access: Boolean,
    initialFilter: InterruptionFilter,
) : NotificationPolicyAccess {
    var filter: InterruptionFilter = initialFilter
        private set

    override fun hasAccess(): Boolean = access

    override fun currentFilter(): InterruptionFilter = filter

    override fun setFilter(filter: InterruptionFilter) {
        this.filter = filter
    }
}
