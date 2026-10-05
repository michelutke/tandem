@preconcurrency import AppKit
import Synchronization

/// Production ``FocusStateSource`` (E72-03 design note): re-reads the Focus state whenever
/// `NSWorkspace` posts an accessibility display options change and yields it when it differs from
/// the last value. Every `changes` access observes independently and stops when its consumer ends.
public struct WorkspaceFocusStateSource: FocusStateSource {
    private let isFocusActive: @Sendable () -> Bool

    public init(
        isFocusActive: @escaping @Sendable () -> Bool = {
            UserDefaults(suiteName: "com.apple.donotdisturbd")?.bool(forKey: "doNotDisturb") ?? false
        }
    ) {
        self.isFocusActive = isFocusActive
    }

    public var changes: AsyncStream<Bool> {
        let isFocusActive = isFocusActive
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let last = Mutex<Bool?>(nil)
            nonisolated(unsafe) let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil,
                queue: nil
            ) { _ in
                let current = isFocusActive()
                let changed = last.withLock { previous in
                    defer { previous = current }
                    return previous != current
                }
                if changed { continuation.yield(current) }
            }
            continuation.onTermination = { _ in
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
            }
        }
    }
}
