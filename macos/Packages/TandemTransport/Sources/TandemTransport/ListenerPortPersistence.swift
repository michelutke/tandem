import Foundation
import Network

/// Remembers the TCP port the Mac listener last bound, so the phone's stored address keeps working
/// across app restarts, sleep/wake and network-path restarts. The port is not a secret.
public protocol ListenerPortStore: Sendable {
    var preferredPort: UInt16? { get }
    func persist(_ port: UInt16)
}

public struct UserDefaultsListenerPortStore: ListenerPortStore, @unchecked Sendable {
    private static let key = "listenerPort"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var preferredPort: UInt16? {
        let stored = defaults.integer(forKey: Self.key)
        return UInt16(exactly: stored).flatMap { $0 == 0 ? nil : $0 }
    }

    public func persist(_ port: UInt16) {
        defaults.set(Int(port), forKey: Self.key)
    }
}

public enum ListenerBindOutcome: Sendable, Equatable {
    case ready(port: UInt16)
    case failed
}

/// Starts a listener and reports whether it bound. A seam so ``ListenerController``'s port
/// fallback is testable without opening sockets.
public protocol ListenerBinder: Sendable {
    func bind(_ listener: NWListener) -> ListenerBindOutcome
}

public struct NWListenerBinder: ListenerBinder {
    private let timeout: DispatchTimeInterval

    public init(timeout: DispatchTimeInterval = .seconds(3)) {
        self.timeout = timeout
    }

    public func bind(_ listener: NWListener) -> ListenerBindOutcome {
        let outcome = OutcomeBox()
        let semaphore = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                outcome.set(listener.port.map { .ready(port: $0.rawValue) } ?? .failed)
            case .failed, .cancelled:
                outcome.set(.failed)
            default:
                return
            }
            semaphore.signal()
        }
        listener.start(queue: .global())
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            listener.stateUpdateHandler = nil
            return .failed
        }
        listener.stateUpdateHandler = nil
        return outcome.value
    }

    private final class OutcomeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = ListenerBindOutcome.failed

        var value: ListenerBindOutcome {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }

        func set(_ outcome: ListenerBindOutcome) {
            lock.lock()
            stored = outcome
            lock.unlock()
        }
    }
}
