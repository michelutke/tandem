package dev.tandem.feature.notifications

/** In-memory [FocusFilterRecord]; [initial] models a value persisted by an earlier process. */
class FakeFocusFilterRecord(
    initial: InterruptionFilter? = null,
) : FocusFilterRecord {
    private var recorded: InterruptionFilter? = initial

    override fun load(): InterruptionFilter? = recorded

    override fun save(filter: InterruptionFilter) {
        recorded = filter
    }

    override fun clear() {
        recorded = null
    }
}
