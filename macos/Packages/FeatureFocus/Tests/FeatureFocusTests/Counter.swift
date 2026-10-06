import Synchronization

final class Counter: Sendable {
    private let value = Mutex(0)

    func increment() -> Int {
        value.withLock { current in
            defer { current += 1 }
            return current
        }
    }
}
