import Foundation
import TandemProtocol

/// Bridges zero or more successive ``TandemSession``s for the same paired peer into long-lived
/// ``AsyncStream``s (E22-11, E15-16): ``MenuBarViewModel``/``ErrorBannerViewModel`` are each
/// constructed once, at ``MenuContentView`` init, and each observe their own ``makeStream()`` for
/// the rest of the app's lifetime (an `AsyncStream` has a single consumer, so every subscriber gets
/// its own, starting with the latest state already forwarded) -- unlike a bare
/// ``TandemSession/state``, which finishes the moment that one session ``close()``s, this relay
/// just keeps forwarding once ``attach(_:)`` is called again for the peer's next reconnect, so
/// neither view model ever needs to be told about a new ``TandemSession`` instance directly.
///
/// ``AppComposition`` is the only caller: it builds one relay per currently-paired peer and passes
/// ``attach(_:)`` as ``TandemTransport/NWListenerFactory``'s own `onSessionRegistered` hook, filtered
/// to that peer's fingerprint.
actor ConnectionStateRelay {
    private let subscribers = Subscribers()
    private var forwardTask: Task<Void, Never>?

    /// A new long-lived stream of this peer's connection state: starts with the latest state
    /// already forwarded (if any), then every later one. Never finishes on its own -- only when
    /// this relay itself is deallocated (process lifetime, in practice).
    nonisolated func makeStream() -> AsyncStream<ConnectionStateMachine.ConnectionState> {
        subscribers.makeStream()
    }

    /// Starts forwarding `session`'s own ``TandemSession/state`` to every stream, replacing whatever
    /// this relay was previously forwarding from (an earlier, now-closed session for the same peer).
    func attach(_ session: any TandemSession) {
        forwardTask?.cancel()
        let sessionState = session.state
        let subscribers = self.subscribers
        forwardTask = Task {
            for await state in sessionState {
                subscribers.yield(state)
            }
        }
    }
}

final class Subscribers: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<ConnectionStateMachine.ConnectionState>.Continuation] = [:]
    var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }
    private var latest: ConnectionStateMachine.ConnectionState?

    func makeStream() -> AsyncStream<ConnectionStateMachine.ConnectionState> {
        let (stream, continuation) = AsyncStream<ConnectionStateMachine.ConnectionState>.makeStream()
        lock.lock()
        defer { lock.unlock() }
        if let latest {
            continuation.yield(latest)
        }
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in self?.remove(id) }
        return stream
    }

    func yield(_ state: ConnectionStateMachine.ConnectionState) {
        lock.lock()
        defer { lock.unlock() }
        latest = state
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        continuations.removeValue(forKey: id)
    }
}
