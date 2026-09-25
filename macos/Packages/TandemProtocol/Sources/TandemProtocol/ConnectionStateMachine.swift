import Foundation

/// Per-connection state machine for a Mac-side accepted incoming connection (docs/protocol/
/// SPEC.md #handshake-and-tls-profile "Failure behavior", #errors-and-close-codes,
/// #timeouts-connection-limits-and-resource-caps; invariant 5). Swift counterpart to the Android
/// `ConnectionStateMachine` (E12-08); one instance exists per accepted connection -- the Mac can
/// hold several concurrently (E12-18) -- and it never dials, so unlike the Android machine it has
/// no `Connecting` state: its lifecycle starts once the listener has already accepted a socket.
///
/// ``transition(from:event:)`` is a pure function: given a state and an event it returns the next
/// state, or `nil` if the event is illegal in that state, in which case the caller (``handle(_:)``)
/// leaves ``state`` unchanged and reports the event as rejected. The actor wrapped around it owns
/// only the injected `Clock<Duration>` used to race the TLS-handshake deadline (SPEC.md §10,
/// E01-22) and the ``states`` stream this connection's transitions are published on. This machine
/// never touches `Network` or any real socket itself -- every event is driven by a caller
/// observing the real listener/handshake (E12-01, E12-02, E12-07) -- and `TandemProtocol` may not
/// depend on `TandemTransport` (PRD module rules: transport depends on protocol, never the
/// reverse).
actor ConnectionStateMachine {

    /// Every state this machine's connection can be in.
    enum ConnectionState: Sendable, Equatable {
        /// Before this connection was ever accepted (`reason == nil`, the only value ``handle(_:)``
        /// ever starts from), or after a `Ready` connection's socket closed (`reason` is then the
        /// close description).
        case disconnected(reason: String?)
        case accepted
        case tlsHandshaking
        case helloExchange
        case ready
        /// A fatal, fail-closed outcome (invariant 5). `CloseCode` is the canonical close-code
        /// enumeration (docs/protocol/SPEC.md #errors-and-close-codes) -- never an empty/absent
        /// reason.
        case failed(CloseCode)
    }

    /// Inputs this machine reacts to.
    enum Event: Sendable, Equatable {
        case incomingConnection
        case handshakeStarted
        case handshakeCompleted
        case compatibleHelloReceived
        case handshakeError(CloseCode)
        case socketClosed(reason: String)
    }

    /// TLS handshake deadline: 10 s from TCP accept, Mac side (docs/protocol/SPEC.md §10,
    /// E01-22). Races from ``Event/incomingConnection`` until ``Event/handshakeCompleted``;
    /// cancelled the moment this connection leaves ``ConnectionState/accepted`` or
    /// ``ConnectionState/tlsHandshaking`` for any reason.
    static let handshakeDeadline: Duration = .seconds(10)

    private let clock: any Clock<Duration>
    private(set) var state: ConnectionState = .disconnected(reason: nil)
    private var deadlineTask: Task<Void, Never>?
    private let continuation: AsyncStream<ConnectionState>.Continuation

    /// Every state this connection has been in, in order, starting with
    /// ``ConnectionState/disconnected(reason:)`` (`reason == nil`) at construction. Finishes once
    /// this connection reaches a terminal state (``ConnectionState/failed(_:)`` or a `Ready`
    /// connection's ``ConnectionState/disconnected(reason:)``).
    nonisolated let states: AsyncStream<ConnectionState>

    init(clock: any Clock<Duration>) {
        self.clock = clock
        let (states, continuation) = AsyncStream<ConnectionState>.makeStream(bufferingPolicy: .unbounded)
        self.states = states
        self.continuation = continuation
        continuation.yield(.disconnected(reason: nil))
    }

    /// Applies `event` to ``state``.
    ///
    /// - Returns: `true` if ``transition(from:event:)`` accepted `event` -- ``state`` changed and
    ///   was published on ``states``; `false` if `event` is illegal from the current ``state``,
    ///   which is then left unchanged (acceptance: "An illegal event leaves the state unchanged
    ///   and is reported as rejected").
    @discardableResult
    func handle(_ event: Event) -> Bool {
        guard let next = Self.transition(from: state, event: event) else { return false }
        state = next
        continuation.yield(next)

        switch (event, next) {
        case (.incomingConnection, _):
            startHandshakeDeadline()
        case (_, .helloExchange), (_, .ready):
            cancelHandshakeDeadline()
        default:
            break
        }

        switch next {
        case .failed:
            cancelHandshakeDeadline()
            continuation.finish()
        case .disconnected(let reason) where reason != nil:
            cancelHandshakeDeadline()
            continuation.finish()
        default:
            break
        }

        return true
    }

    private func startHandshakeDeadline() {
        deadlineTask?.cancel()
        let clock = clock
        deadlineTask = Task { [weak self] in
            try? await clock.sleep(for: Self.handshakeDeadline)
            guard !Task.isCancelled else { return }
            await self?.handshakeDeadlineElapsed()
        }
    }

    private func cancelHandshakeDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil
    }

    private func handshakeDeadlineElapsed() {
        handle(.handshakeError(.protocolTimeout))
    }

    /// The pure reducer (see this type's own documentation). `nil` means `event` is illegal from
    /// `state`; the caller must leave `state` unchanged.
    static func transition(from state: ConnectionState, event: Event) -> ConnectionState? {
        switch (state, event) {
        case (.disconnected(nil), .incomingConnection):
            return .accepted
        case (.accepted, .handshakeStarted):
            return .tlsHandshaking
        case (.tlsHandshaking, .handshakeCompleted):
            return .helloExchange
        case (.helloExchange, .compatibleHelloReceived):
            return .ready
        case (.ready, .socketClosed(let reason)):
            return .disconnected(reason: reason)
        case (.accepted, .handshakeError(let code)),
             (.tlsHandshaking, .handshakeError(let code)),
             (.helloExchange, .handshakeError(let code)),
             (.ready, .handshakeError(let code)):
            return .failed(code)
        default:
            return nil
        }
    }
}
