package dev.tandem.feature.status

import app.cash.turbine.test
import dev.tandem.protocol.v1.NetworkType
import dev.tandem.protocol.v1.deviceStatus
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * StatusAggregator tests (E23-02, `docs/planning/backlog/phase-2.yaml` E23-02's `tdd:` list):
 * each source is a fake `MutableStateFlow` the test drives directly, and the combined `status`
 * Flow is asserted with Turbine.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class StatusAggregatorTest {
    @Test
    fun statusAggregator_batteryLevelChanged_emitsDeviceStatusWithNewLevel() =
        runTest {
            val battery = FakeBatteryStatusSource(BatteryStatus(level = 50, isCharging = false))
            val aggregator = newAggregator(battery = battery)

            aggregator.status.test {
                assertEquals(
                    deviceStatus {
                        batteryLevel = 50
                        isCharging = false
                        networkType = NetworkType.NETWORK_TYPE_WIFI
                        signalLevel = 3
                    },
                    awaitItem(),
                )

                battery.batteryStatus.value = BatteryStatus(level = 80, isCharging = true)

                assertEquals(
                    deviceStatus {
                        batteryLevel = 80
                        isCharging = true
                        networkType = NetworkType.NETWORK_TYPE_WIFI
                        signalLevel = 3
                    },
                    awaitItem(),
                )
            }
        }

    @Test
    fun statusAggregator_wifiToCellular_emitsNetworkTypeCellular() =
        runTest {
            val networkType = FakeNetworkTypeSource(NetworkType.NETWORK_TYPE_WIFI)
            val aggregator = newAggregator(networkType = networkType)

            aggregator.status.test {
                assertEquals(NetworkType.NETWORK_TYPE_WIFI, awaitItem().networkType)

                networkType.networkType.value = NetworkType.NETWORK_TYPE_CELLULAR

                assertEquals(NetworkType.NETWORK_TYPE_CELLULAR, awaitItem().networkType)
            }
        }

    @Test
    fun statusAggregator_signalLevelChanged_emitsDeviceStatusWithNewLevel() =
        runTest {
            val signal = FakeSignalStrengthSource(2)
            val aggregator = newAggregator(signal = signal)

            aggregator.status.test {
                assertEquals(2, awaitItem().signalLevel)

                signal.signalLevel.value = 4

                assertEquals(4, awaitItem().signalLevel)
            }
        }

    @Test
    fun statusAggregator_identicalValues_noEmission() =
        runTest {
            val battery = FakeBatteryStatusSource(BatteryStatus(level = 50, isCharging = false))
            val aggregator = newAggregator(battery = battery)

            aggregator.status.test {
                awaitItem()

                battery.batteryStatus.value = BatteryStatus(level = 50, isCharging = false)

                expectNoEvents()
            }
        }

    private fun newAggregator(
        battery: FakeBatteryStatusSource = FakeBatteryStatusSource(BatteryStatus(level = 50, isCharging = false)),
        networkType: FakeNetworkTypeSource = FakeNetworkTypeSource(NetworkType.NETWORK_TYPE_WIFI),
        signal: FakeSignalStrengthSource = FakeSignalStrengthSource(3),
    ): StatusAggregator = StatusAggregator(battery, networkType, signal)
}

private class FakeBatteryStatusSource(
    initial: BatteryStatus,
) : BatteryStatusSource {
    override val batteryStatus = MutableStateFlow(initial)
}

private class FakeNetworkTypeSource(
    initial: NetworkType,
) : NetworkTypeSource {
    override val networkType = MutableStateFlow(initial)
}

private class FakeSignalStrengthSource(
    initial: Int?,
) : SignalStrengthSource {
    override val signalLevel = MutableStateFlow(initial)
}
