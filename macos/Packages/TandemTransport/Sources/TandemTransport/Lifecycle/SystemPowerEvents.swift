import Foundation

/// Mac sleep/wake power events (E20-10, PRD F-3.4, UC-04). Abstracted so neither
/// ``SleepWakeController`` nor E22-08's menu bar view model ever imports `AppKit`/`NSWorkspace`
/// directly -- both observe this protocol instead.
public enum SystemPowerEvent: Sendable, Equatable {
    case willSleep
    case didWake
}

/// Seam over `NSWorkspace`'s sleep/wake notifications. ``events`` never finishes; the production
/// adapter is ``WorkspacePowerEvents``.
public protocol SystemPowerEvents: Sendable {
    var events: AsyncStream<SystemPowerEvent> { get }
}
