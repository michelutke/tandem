import TandemProtocol

/// Bridges zero or more successive ``TandemSession``s for the same paired peer into one long-lived
/// ``AsyncStream`` (E22-11): ``MenuBarViewModel``/``ErrorBannerViewModel`` are each constructed once,
/// at ``MenuContentView`` init, and observe ``stream`` for the rest of the app's lifetime -- unlike
/// a bare ``TandemSession/state``, which finishes the moment that one session ``close()``s, this
/// relay just keeps forwarding once ``attach(_:)`` is called again for the peer's next reconnect, so
/// neither view model ever needs to be told about a new ``TandemSession`` instance directly.
///
/// ``AppComposition`` is the only caller: it builds one relay per currently-paired peer and passes
/// ``attach(_:)`` as ``TandemTransport/NWListenerFactory``'s own `onSessionRegistered` hook, filtered
/// to that peer's fingerprint.
actor ConnectionStateRelay {
    /// The long-lived stream ``MenuBarViewModel``/``ErrorBannerViewModel`` observe. Never finishes
    /// on its own -- only when this relay itself is deallocated (process lifetime, in practice).
    nonisolated let stream: AsyncStream<ConnectionStateMachine.ConnectionState>

    private let continuation: AsyncStream<ConnectionStateMachine.ConnectionState>.Continuation
    private var forwardTask: Task<Void, Never>?

    init() {
        var continuation: AsyncStream<ConnectionStateMachine.ConnectionState>.Continuation!
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    /// Starts forwarding `session`'s own ``TandemSession/state`` onto ``stream``, replacing whatever
    /// this relay was previously forwarding from (an earlier, now-closed session for the same peer).
    func attach(_ session: any TandemSession) {
        forwardTask?.cancel()
        let sessionState = session.state
        let continuation = self.continuation
        forwardTask = Task {
            for await state in sessionState {
                continuation.yield(state)
            }
        }
    }
}
