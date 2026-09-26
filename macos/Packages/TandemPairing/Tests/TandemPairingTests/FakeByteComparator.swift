import Foundation
@testable import TandemPairing

/// A ``ByteComparator`` fake whose call count is inspectable -- proves ``PairProofVerifier``
/// invokes the comparator exactly once per attempt, and never at all when it rejects early
/// without computing anything.
final class SpyByteComparator: ByteComparator, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let result: Bool

    init(result: Bool) {
        self.result = result
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func compare(_ lhs: Data, _ rhs: Data) -> Bool {
        lock.lock()
        count += 1
        lock.unlock()
        return result
    }
}

/// A lock-protected mutable value, for closures that need to read/write shared state across the
/// `@Sendable` provider callbacks ``PairProofVerifier`` takes.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ initial: Value) {
        stored = initial
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            stored = newValue
        }
    }
}
