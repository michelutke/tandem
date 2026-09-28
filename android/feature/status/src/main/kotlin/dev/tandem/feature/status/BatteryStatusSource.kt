package dev.tandem.feature.status

import kotlinx.coroutines.flow.Flow

/** Battery charge percentage (0-100) and charging state, as reported by [BatteryStatusSource]. */
data class BatteryStatus(
    val level: Int,
    val isCharging: Boolean,
)

/**
 * A stream of battery readings (E23-02), fed into [StatusAggregator]. The production
 * implementation ([BatteryReceiverStatusSource]) derives this from `ACTION_BATTERY_CHANGED`;
 * tests substitute a fake.
 */
interface BatteryStatusSource {
    val batteryStatus: Flow<BatteryStatus>
}
