import AppKit
import Foundation

/// Production ``SystemPowerEvents`` over an injected `NotificationCenter` -- ordinarily
/// `NSWorkspace.shared.notificationCenter`, taken as a parameter and never referenced directly, so
/// a test can post `NSWorkspace.willSleepNotification`/`didWakeNotification` on a plain
/// `NotificationCenter` instance instead of touching the real shared workspace (E20-10).
public final class WorkspacePowerEvents: SystemPowerEvents, @unchecked Sendable {

    public let events: AsyncStream<SystemPowerEvent>
    private let continuation: AsyncStream<SystemPowerEvent>.Continuation
    private let notificationCenter: NotificationCenter
    private let willSleepObserver: NSObjectProtocol
    private let didWakeObserver: NSObjectProtocol

    public init(notificationCenter: NotificationCenter) {
        let (events, continuation) = AsyncStream<SystemPowerEvent>.makeStream()
        self.events = events
        self.continuation = continuation
        self.notificationCenter = notificationCenter

        willSleepObserver = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: nil
        ) { _ in continuation.yield(.willSleep) }

        didWakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { _ in continuation.yield(.didWake) }
    }

    deinit {
        notificationCenter.removeObserver(willSleepObserver)
        notificationCenter.removeObserver(didWakeObserver)
        continuation.finish()
    }
}
