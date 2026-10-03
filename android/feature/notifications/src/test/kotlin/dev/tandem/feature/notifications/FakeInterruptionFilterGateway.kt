package dev.tandem.feature.notifications

/**
 * Recording fake for [InterruptionFilterGateway] (E72-04): models policy access and the current
 * interruption filter as plain state, and records every [setFilter] call in [appliedFilters].
 */
class FakeInterruptionFilterGateway(
    private val access: Boolean,
    initialFilter: InterruptionFilter,
) : InterruptionFilterGateway {
    var filter: InterruptionFilter = initialFilter
        private set

    val appliedFilters = mutableListOf<InterruptionFilter>()

    override fun hasPolicyAccess(): Boolean = access

    override fun currentFilter(): InterruptionFilter = filter

    override fun setFilter(filter: InterruptionFilter) {
        appliedFilters += filter
        this.filter = filter
    }
}
