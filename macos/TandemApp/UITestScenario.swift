#if DEBUG
import Foundation

/// DEBUG-only XCUITest scenario hook (E00-26): the app reads `-UITestScenario <name>` only
/// under `#if DEBUG` so UI tests can drive a deterministic view without a phone. This type and
/// every caller of it must not exist in Release (invariant 2); a CI check scans the Release
/// binary for the `UITestScenario` string.
enum UITestScenario: String {
    /// No paired phone. Phase 0 seeds nothing extra: the menu already shows this state by
    /// default. Scenarios that need a seeded in-memory store or a fake session (E12-12) land
    /// once that dependency exists — at which point TandemApp's Debug configuration links
    /// TandemTestSupport (E00-24's documented exception). Not wired here: Xcode links a Swift
    /// package product's whole module into every configuration once any target dependency
    /// references it, regardless of `#if DEBUG` gating or `embed`/`link` settings, so making that
    /// link genuinely Debug-only needs its own per-configuration mechanism, verified against
    /// `nm`/`strings` on the Release product, when a scenario first needs it.
    case notPaired

    /// A paired peer whose session is `Ready` (E22-01): the menu bar shows "Connected to
    /// <peer name>" and the battery placeholder, backed by a ``FakeTandemSession`` (E12-12)
    /// seeded via `@testable import TandemProtocol`.
    case pairedConnected

    /// Fail-closed error state: version mismatch (E12-10).
    case failClosedError

    static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments) -> UITestScenario? {
        guard let flagIndex = arguments.firstIndex(of: "-UITestScenario"),
              arguments.indices.contains(flagIndex + 1) else { return nil }
        return UITestScenario(rawValue: arguments[flagIndex + 1])
    }

    /// Whether a `-UITestSeedDeviceStatus` launch argument accompanies ``pairedConnected`` --
    /// seeds a `DeviceStatus` frame (E23-04) in addition to the `Ready` state, so
    /// `menuBarExtra_seededDeviceStatus_showsBatteryPercentAndNetworkLabel` can assert on the
    /// formatted battery/network/signal strings without perturbing the existing
    /// `showsPeerNameAndBatteryPlaceholder` scenario (no flag -> no `DeviceStatus` -> placeholder).
    static func deviceStatusSeedRequested(_ arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains("-UITestSeedDeviceStatus")
    }
}
#endif
