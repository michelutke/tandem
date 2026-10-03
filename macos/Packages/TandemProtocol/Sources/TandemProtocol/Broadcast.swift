import Foundation

/// Delivers every published element to every current subscriber, in publish order, each through its
/// own unbounded `AsyncStream` -- so several consumers of one source never split its elements the
/// way two iterators over a single `AsyncStream` do. Elements published before the first
/// ``subscribe()`` are held for that first subscriber, so a source that starts producing before its
/// consumers attach loses nothing; later subscribers see only elements published after they
/// subscribed. ``finish()`` finishes every subscriber's stream, and a stream subscribed afterwards
/// finishes immediately (after any held elements).
public final class Broadcast<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [UInt64: AsyncStream<Element>.Continuation] = [:]
    private var nextSubscriberId: UInt64 = 0
    private var heldForFirstSubscriber: [Element] = []
    private var hasHadSubscriber = false
    private var isFinished = false

    public init() {}

    public func subscribe() -> AsyncStream<Element> {
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: .unbounded)
        let (held, id) = lock.withLock { () -> ([Element], UInt64?) in
            let held = hasHadSubscriber ? [] : heldForFirstSubscriber
            heldForFirstSubscriber = []
            hasHadSubscriber = true
            guard !isFinished else { return (held, nil) }
            let id = nextSubscriberId
            nextSubscriberId += 1
            subscribers[id] = continuation
            return (held, id)
        }
        held.forEach { continuation.yield($0) }
        if let id {
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { _ = self?.subscribers.removeValue(forKey: id) }
            }
        } else {
            continuation.finish()
        }
        return stream
    }

    public func publish(_ element: Element) {
        let targets = lock.withLock { () -> [AsyncStream<Element>.Continuation] in
            guard !isFinished else { return [] }
            if !hasHadSubscriber { heldForFirstSubscriber.append(element) }
            return Array(subscribers.values)
        }
        targets.forEach { $0.yield(element) }
    }

    public func finish() {
        let targets = lock.withLock { () -> [AsyncStream<Element>.Continuation] in
            isFinished = true
            let targets = Array(subscribers.values)
            subscribers = [:]
            return targets
        }
        targets.forEach { $0.finish() }
    }
}
