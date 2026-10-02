import FeatureNotifications
import Foundation

/// Test fixture (E30-15): a ``ScreenLockState`` whose lock state a test flips directly.
final class FakeScreenLockState: ScreenLockState, @unchecked Sendable {
    let changes: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation
    private let lock = NSLock()
    private var locked: Bool

    init(isLocked: Bool = false) {
        locked = isLocked
        (changes, continuation) = AsyncStream<Bool>.makeStream()
    }

    var isLocked: Bool {
        lock.withLock { locked }
    }

    func setLocked(_ value: Bool) {
        lock.withLock { locked = value }
        continuation.yield(value)
    }
}

/// Test fixture (E30-15): a thread-safe, flippable stand-in for the Mac "hide content when
/// locked" setting.
final class FakeHideWhenLockedSetting: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    var isEnabled: Bool {
        lock.withLock { enabled }
    }

    func set(_ value: Bool) {
        lock.withLock { enabled = value }
    }
}
