import Testing

@testable import TandemApp
@testable import TandemProtocol

/// E23-04 tdd (unit): ``DeviceStatusViewModel`` formatting a `DeviceStatus` received on the
/// STATUS channel of the E12-12 `FakeTandemSession`, the same seam ``MenuBarViewModelTests``
/// already uses for connection state.
@Suite("DeviceStatusViewModel")
struct DeviceStatusViewModelTests {
    private static func deviceStatus(
        batteryLevel: Int32,
        isCharging: Bool,
        networkType: Tandem_V1_NetworkType,
        signalLevel: Int32
    ) -> Tandem_V1_DeviceStatus {
        var status = Tandem_V1_DeviceStatus()
        status.batteryLevel = batteryLevel
        status.isCharging = isCharging
        status.networkType = networkType
        status.signalLevel = signalLevel
        return status
    }

    // MARK: - deviceStatusViewModel_statusReceived_formatsBatteryChargingNetworkSignal

    @Test
    func deviceStatusViewModel_statusReceived_formatsBatteryChargingNetworkSignal() async throws {
        let session = FakeTandemSession()
        let viewModel = await DeviceStatusViewModel(session: session)

        let status = Self.deviceStatus(batteryLevel: 82, isCharging: true, networkType: .cellular, signalLevel: 3)
        await session.inject(InboundFrame(channel: .status, seq: 1, ack: 0, payload: .deviceStatus(status)))

        // This package's `injected_clock_only` SwiftLint rule (E00-24) bans the usual real-time
        // sleep/now APIs outright, even in test files -- so this yields cooperatively, bounded by
        // an iteration count rather than a wall-clock deadline, matching `MenuBarViewModelTests`'s
        // own wait loop.
        var attempts = 0
        while await viewModel.batteryText == nil, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        #expect(await viewModel.batteryText == "Battery 82% · Charging")
        #expect(await viewModel.batteryPercent == 82)
        #expect(await viewModel.networkText == "Cellular")
        #expect(await viewModel.signalBars == 3)
        #expect(await viewModel.signalAccessibilityValue == "3 of 4 bars")
    }

    // MARK: - deviceStatusViewModel_secondStatus_replacesDisplayedValues

    @Test
    func deviceStatusViewModel_secondStatus_replacesDisplayedValues() async throws {
        let session = FakeTandemSession()
        let viewModel = await DeviceStatusViewModel(session: session)

        let first = Self.deviceStatus(batteryLevel: 82, isCharging: true, networkType: .cellular, signalLevel: 3)
        await session.inject(InboundFrame(channel: .status, seq: 1, ack: 0, payload: .deviceStatus(first)))

        var attempts = 0
        while await viewModel.batteryText == nil, attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        let second = Self.deviceStatus(batteryLevel: 40, isCharging: false, networkType: .wifi, signalLevel: 0)
        await session.inject(InboundFrame(channel: .status, seq: 2, ack: 0, payload: .deviceStatus(second)))

        attempts = 0
        while await viewModel.batteryText != "Battery 40%", attempts < 10_000 {
            await Task.yield()
            attempts += 1
        }

        #expect(await viewModel.batteryText == "Battery 40%")
        #expect(await viewModel.networkText == "Wi-Fi")
        #expect(await viewModel.signalBars == nil)
        #expect(await viewModel.signalAccessibilityValue == nil)
    }
}
