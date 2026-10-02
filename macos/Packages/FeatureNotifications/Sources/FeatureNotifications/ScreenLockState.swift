import Foundation

/// Seam over the Mac's screen-lock state (E30-15), so lock-screen hiding is testable with a fake.
public protocol ScreenLockState: Sendable {
    var isLocked: Bool { get }

    /// Emits the new `isLocked` value on every lock or unlock.
    var changes: AsyncStream<Bool> { get }
}

/// Production ``ScreenLockState`` over an injected `NotificationCenter` -- ordinarily
/// `DistributedNotificationCenter.default()`, taken as a parameter and never referenced directly,
/// so a test can post `com.apple.screenIsLocked`/`com.apple.screenIsUnlocked` on a plain
/// `NotificationCenter` instance.
public final class DistributedScreenLockState: ScreenLockState, @unchecked Sendable {
    public let changes: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var locked = false
    private var observers: [NSObjectProtocol] = []

    public init(notificationCenter: NotificationCenter) {
        (changes, continuation) = AsyncStream<Bool>.makeStream()
        self.notificationCenter = notificationCenter
        observers = [
            observe(Notification.Name("com.apple.screenIsLocked"), locked: true),
            observe(Notification.Name("com.apple.screenIsUnlocked"), locked: false)
        ]
    }

    deinit {
        observers.forEach(notificationCenter.removeObserver)
        continuation.finish()
    }

    public var isLocked: Bool {
        lock.withLock { locked }
    }

    private func observe(_ name: Notification.Name, locked newValue: Bool) -> NSObjectProtocol {
        notificationCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            lock.withLock { locked = newValue }
            continuation.yield(newValue)
        }
    }
}
