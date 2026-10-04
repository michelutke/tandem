import Foundation

/// Which closed reasons make the presenting window disappear on its own (E22-14). `.attemptsExhausted`
/// stays visible so the "Too many tries" screen's Regenerate (E14-11) can be used.
public enum PairingWindowAutoClose {
    public static func shouldClose(closedReason: PairingWindowClosedReason?) -> Bool {
        switch closedReason {
        case .paired, .cancelled, .expired, .declined: return true
        case .attemptsExhausted, nil: return false
        }
    }
}

/// What closing the pairing window by hand means: a pending confirmation is an owner decline
/// (`PairRejected(REJECTED_BY_OWNER)`, SPEC "Mutual confirmation"), anything else a plain cancel.
public enum PairingOwnerClose {
    public static func handle(pending: PairConfirmationViewModel?, host: PairingWindowHost) async {
        if let pending, !pending.isResolved {
            await pending.ownerDidDismiss()
        } else {
            host.cancel()
        }
    }
}

/// The current listener's port, read when each pairing window opens so a listener restarted by
/// sleep/wake or a path change is never advertised under its old port.
public final class ListenerPortSource: @unchecked Sendable {
    private let lock = NSLock()
    private var portProvider: (@Sendable () -> Int?)?

    public init() {}

    public func listenerReplaced(portProvider: @escaping @Sendable () -> Int?) {
        lock.lock()
        self.portProvider = portProvider
        lock.unlock()
    }

    public var port: Int? {
        lock.lock()
        let provider = portProvider
        lock.unlock()
        return provider?()
    }
}

/// Numbers pairing windows so work belonging to a previous window (e.g. a late confirmation
/// delivery) can be told apart from the current one and dropped.
public final class PairingWindowGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0

    public init() {}

    public func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        current += 1
        return current
    }

    public func isCurrent(_ token: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return token == current
    }
}
