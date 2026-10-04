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

    /// A previously-paired peer whose session is not currently `Ready` -- e.g. disconnected
    /// (E22-02): the menu bar shows "Disconnected" and the four quick actions (Send File, Push
    /// Clipboard, Find Phone, Mirror Phone) render but each disabled, backed by the same seeded
    /// ``FakeTandemSession`` (E12-12) approach as ``pairedConnected``, transitioned to
    /// `.disconnected` instead of `.ready`.
    case pairedDisconnected

    /// Fail-closed error state: version mismatch (E12-10).
    case failClosedError

    /// A paired peer whose real-shaped connection state (a ``ConnectionStateRelay`` fed by a
    /// `FakeTandemSession`, the E22-11 production seam) failed with a version mismatch (E15-16):
    /// both the menu bar's state label and the error banner show the version-mismatch error.
    case versionMismatchMenu

    /// Local Network privacy permission denied (E21-03): the menu shows
    /// ``LocalNetworkPermissionViewModel``'s exact explanation text and an "Open System Settings"
    /// button, seeded by a `BonjourPublishError.policyDenied` error on a plain
    /// `AsyncStream<BonjourPublishError>` (TandemTransport, E21-02) rather than a real
    /// `BonjourPublisher` -- no advertise/listener wiring exists in this scenario window.
    case localNetworkDenied

    /// Main window (E22-09), phone offline: the sidebar's state line reads "Offline · seen HH:MM"
    /// with a grey dot, backed by a fixed local time so the assertion is deterministic regardless
    /// of the host's real clock.
    case mainWindowOffline

    /// Main window (E22-09), the selected section's feature is turned off on the phone: the
    /// content area shows the shared "Turned off on the phone." empty state.
    case mainWindowFeatureDisabled

    /// Photo grid (E41-05) over a seeded ``PhotoService`` reporting PARTIAL access: the limited-
    /// access banner and its "Select more on phone" button render without a phone.
    case photoGridPartialAccess

    /// Messages thread list (E50-07) over seeded in-memory SMS and contacts stores: three threads
    /// render newest first, with one resolved contact name, one international number and a badge.
    case threadListSeeded
    /// An incoming call already `ACTIVE` (E52-06): the menu bar's Hang Up item renders.
    case incomingCallActive

    /// One in-flight transfer already at 42% (E40-23): the row shows "42%" and a Cancel button
    /// that flips the row to "Cancelled" through the same cancel closure production wires to E40-20.
    case transferProgressSeeded

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
