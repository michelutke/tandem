package dev.tandem.feature.status

import kotlinx.coroutines.flow.Flow

/**
 * A stream of cellular signal level readings (E23-02), fed into [StatusAggregator]: 0 (none) to 4
 * (full bars), or `null` when unavailable without the `READ_PHONE_STATE` permission this app does
 * not request. `null` is mapped to the proto default (0) at the [StatusAggregator] boundary.
 */
interface SignalStrengthSource {
    val signalLevel: Flow<Int?>
}
