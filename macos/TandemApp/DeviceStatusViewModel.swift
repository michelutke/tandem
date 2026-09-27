import Foundation
import Observation
import TandemProtocol

/// Presents the phone's `DeviceStatus` (STATUS channel, PRD F-4.3; docs/protocol/SPEC.md
/// #status-channel, E23-01) for the menu bar dropdown and the paired-devices row: battery
/// percentage (with a charging suffix), network type, and -- cellular only, per
/// `docs/planning/decisions.md` D-51 -- signal strength as 0-4 bars. Wi-Fi and "no network" never
/// carry a signal reading (the phone's own `TelephonyManager` source is unset off cellular,
/// E23-02), so ``signalBars``/``signalAccessibilityValue`` are `nil` in both those cases.
///
/// Presentation-independent -- no `SwiftUI` import -- unit-tested against the E12-12
/// `FakeTandemSession`'s own STATUS stream (`@testable import TandemProtocol`), the same seam
/// ``MenuBarViewModel`` already uses for connection state. ``MenuBarContentView`` is its SwiftUI
/// presentation; `PairedDevicesViewModel` (`TandemDevices`) surfaces the same ``batteryText`` on
/// the paired-devices row.
@MainActor
@Observable
final class DeviceStatusViewModel {
    /// `nil` until the first `DeviceStatus` arrives -- callers fall back to their own placeholder
    /// (``MenuBarViewModel/batteryPlaceholder``) until then.
    private(set) var batteryText: String?

    /// One of "Wi-Fi", "Cellular", or "No network" -- `nil` until the first `DeviceStatus` arrives.
    private(set) var networkText: String?

    /// 0-4, cellular only (D-51); `nil` until a status arrives, or whenever ``networkText`` isn't
    /// "Cellular".
    private(set) var signalBars: Int?

    /// Accessibility value for ``signalBars``, e.g. "3 of 4 bars" -- `nil` exactly when
    /// ``signalBars`` is.
    private(set) var signalAccessibilityValue: String?

    @ObservationIgnored
    private nonisolated(unsafe) var observationTask: Task<Void, Never>?

    /// - Parameter session: The paired session to read the STATUS channel from, or `nil` if no
    ///   peer is paired yet -- every property then stays `nil`. Takes the whole session (rather
    ///   than an already-opened stream, unlike ``MenuBarViewModel``'s `stateStream`) because
    ///   ``TandemSession/receive(_:)`` is itself `async`; this type owns that one hop instead of
    ///   pushing it onto every call site.
    init(session: (any TandemSession)?) {
        if let session {
            observe(session)
        }
    }

    deinit {
        observationTask?.cancel()
    }

    private func observe(_ session: any TandemSession) {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            let stream = await session.receive(.status)
            for await frame in stream {
                guard !Task.isCancelled else { return }
                guard case .deviceStatus(let status)? = frame.payload else { continue }
                self?.apply(status)
            }
        }
    }

    private func apply(_ status: Tandem_V1_DeviceStatus) {
        batteryText = Self.formatBattery(status)
        networkText = Self.formatNetwork(status.networkType)
        if status.networkType == .cellular {
            let bars = Int(status.signalLevel)
            signalBars = bars
            signalAccessibilityValue = "\(bars) of 4 bars"
        } else {
            signalBars = nil
            signalAccessibilityValue = nil
        }
    }

    /// "Battery 82%", plus " · Charging" while `is_charging` (backlog E23-04 "UI strings (exact)").
    static func formatBattery(_ status: Tandem_V1_DeviceStatus) -> String {
        status.isCharging
            ? "Battery \(status.batteryLevel)% · Charging"
            : "Battery \(status.batteryLevel)%"
    }

    /// "Wi-Fi", "Cellular", or "No network" (backlog E23-04 "UI strings (exact)") --
    /// unspecified/offline/unrecognized all fold into "No network", since none of them is a real
    /// connectivity state this protocol ever intentionally sends.
    static func formatNetwork(_ networkType: Tandem_V1_NetworkType) -> String {
        switch networkType {
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        default: return "No network"
        }
    }
}
