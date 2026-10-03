import Foundation

/// Delivers every published element to every current subscriber, in publish order, each through its
/// own unbounded `AsyncStream` -- so several consumers of one source never split its elements the
/// way two iterators over a single `AsyncStream` do. Elements published before the first
/// ``subscribe()`` are held for that first subscriber, so a source that starts producing before its
/// consumers attach loses nothing; later subscribers see only elements published after they
/// subscribed. ``finish()`` finishes every subscriber's stream, and a stream subscribed afterwards
/// finishes immediately (after any held elements).
///
/// A publisher that must not outrun its slowest consumer calls ``awaitCapacity(limit:)`` before
/// each ``publish(_:)``; each subscriber reports an element taken through the closure
/// ``subscribe()`` returns beside its stream.
public final class Broadcast<Element: Sendable>: @unchecked Sendable {
    private struct Subscriber {
        let continuation: AsyncStream<Element>.Continuation
        var outstanding: Int
    }

    private struct Waiter {
        let limit: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var subscribers: [UInt64: Subscriber] = [:]
    private var waiters: [Waiter] = []
    private var nextSubscriberId: UInt64 = 0
    private var heldForFirstSubscriber: [Element] = []
    private var hasHadSubscriber = false
    private var isFinished = false

    public init() {}

    public func subscribe() -> AsyncStream<Element> {
        subscribeReportingConsumption().stream
    }

    public func subscribeReportingConsumption() -> (stream: AsyncStream<Element>, consumed: @Sendable () -> Void) {
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: .unbounded)
        let id = lock.withLock { () -> UInt64? in
            let held = hasHadSubscriber ? [] : heldForFirstSubscriber
            heldForFirstSubscriber = []
            hasHadSubscriber = true
            held.forEach { continuation.yield($0) }
            guard !isFinished else { return nil }
            let id = nextSubscriberId
            nextSubscriberId += 1
            subscribers[id] = Subscriber(continuation: continuation, outstanding: held.count)
            return id
        }
        guard let id else {
            continuation.finish()
            return (stream, {})
        }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            let ready = lock.withLock { () -> [Waiter] in
                subscribers.removeValue(forKey: id)
                return takeSatisfiedWaiters()
            }
            ready.forEach { $0.continuation.resume() }
        }
        return (stream, { [weak self] in self?.consumed(id) })
    }

    public func publish(_ element: Element) {
        let targets = lock.withLock { () -> [AsyncStream<Element>.Continuation] in
            guard !isFinished else { return [] }
            if !hasHadSubscriber { heldForFirstSubscriber.append(element) }
            for id in subscribers.keys { subscribers[id]?.outstanding += 1 }
            return subscribers.values.map(\.continuation)
        }
        targets.forEach { $0.yield(element) }
    }

    /// Suspends until every current subscriber holds fewer than `limit` published-but-untaken
    /// elements; returns at once with no subscribers or once finished.
    public func awaitCapacity(limit: Int) async {
        await withCheckedContinuation { continuation in
            let canProceed = lock.withLock { () -> Bool in
                if isFinished || hasCapacity(limit: limit) { return true }
                waiters.append(Waiter(limit: limit, continuation: continuation))
                return false
            }
            if canProceed { continuation.resume() }
        }
    }

    public func finish() {
        let (targets, ready) = lock.withLock { () -> ([AsyncStream<Element>.Continuation], [Waiter]) in
            isFinished = true
            let targets = subscribers.values.map(\.continuation)
            subscribers = [:]
            let ready = waiters
            waiters = []
            return (targets, ready)
        }
        targets.forEach { $0.finish() }
        ready.forEach { $0.continuation.resume() }
    }

    private func consumed(_ id: UInt64) {
        let ready = lock.withLock { () -> [Waiter] in
            subscribers[id]?.outstanding -= 1
            return takeSatisfiedWaiters()
        }
        ready.forEach { $0.continuation.resume() }
    }

    private func hasCapacity(limit: Int) -> Bool {
        subscribers.values.allSatisfy { $0.outstanding < limit }
    }

    private func takeSatisfiedWaiters() -> [Waiter] {
        let ready = waiters.filter { hasCapacity(limit: $0.limit) }
        waiters = waiters.filter { !hasCapacity(limit: $0.limit) }
        return ready
    }
}
