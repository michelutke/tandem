package dev.tandem.feature.status

import dev.tandem.protocol.v1.DeviceStatus
import dev.tandem.protocol.v1.deviceStatus
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged

/**
 * Combines [BatteryStatusSource], [NetworkTypeSource] and [SignalStrengthSource] into
 * [DeviceStatus] updates (E23-02, PRD F-4.3). Publishes once per combination of the three
 * sources' latest values, and again only when that combination actually changes -- identical
 * consecutive values (all three sources re-emitting the same reading) emit nothing.
 */
class StatusAggregator(
    private val batteryStatusSource: BatteryStatusSource,
    private val networkTypeSource: NetworkTypeSource,
    private val signalStrengthSource: SignalStrengthSource,
) {
    val status: Flow<DeviceStatus> =
        combine(
            batteryStatusSource.batteryStatus,
            networkTypeSource.networkType,
            signalStrengthSource.signalLevel,
        ) { battery, networkType, signalLevel ->
            deviceStatus {
                batteryLevel = battery.level
                isCharging = battery.isCharging
                this.networkType = networkType
                this.signalLevel = signalLevel ?: 0
            }
        }.distinctUntilChanged()
}
