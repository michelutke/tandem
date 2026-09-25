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

    static func fromLaunchArguments(_ arguments: [String] = CommandLine.arguments) -> UITestScenario? {
        guard let flagIndex = arguments.firstIndex(of: "-UITestScenario"),
              arguments.indices.contains(flagIndex + 1) else { return nil }
        return UITestScenario(rawValue: arguments[flagIndex + 1])
    }
}
#endif
