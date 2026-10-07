import Network
import Security

/// Owns whether the app's single mTLS listener is running (E12-01). Must never open a socket
/// without a ready identity (UC-01, invariant 4's spirit extended to "no listener without
/// identity"): `start()` consults ``IdentityStateProvider`` first and never invokes
/// ``ListenerFactory`` unless the identity is ``IdentityState/ready(_:)``.
public final class ListenerController: Sendable {

    private let identityStateProvider: any IdentityStateProvider
    private let listenerFactory: any ListenerFactory
    private let port: NWEndpoint.Port
    private let verify: TandemVerifyBlock
    private let clock: any Clock<Duration>
    private let portStore: (any ListenerPortStore)?
    private let binder: any ListenerBinder

    public init(
        identityStateProvider: any IdentityStateProvider,
        listenerFactory: any ListenerFactory,
        port: NWEndpoint.Port,
        verify: @escaping TandemVerifyBlock,
        clock: any Clock<Duration> = ContinuousClock(),
        portStore: (any ListenerPortStore)? = nil,
        binder: any ListenerBinder = NWListenerBinder()
    ) {
        self.identityStateProvider = identityStateProvider
        self.listenerFactory = listenerFactory
        self.port = port
        self.verify = verify
        self.clock = clock
        self.portStore = portStore
        self.binder = binder
    }

    /// A running listener paired with the ``ConnectionAdmission`` instance backing it -- the only
    /// place that instance is reachable, since ``ListenerFactory/makeListener(identity:port:verify:admission:)``
    /// takes it as a parameter but never hands it back. ``ProductionListenerControl`` (E20-10,
    /// E20-11) holds onto this so its own `stop()` can reach ``ConnectionAdmission/cancelAllReady()``.
    public struct StartedListener: Sendable {
        public let listener: NWListener
        public let admission: ConnectionAdmission
    }

    /// Starts the listener if, and only if, the identity is ready. Returns `nil` (never invoking
    /// ``ListenerFactory``) when the identity is `.missing` or `.error`. Each call builds a fresh
    /// ``ConnectionAdmission`` (E12-18), so a restarted listener starts with a clean pre-auth
    /// budget and throttle state.
    @discardableResult
    public func start() throws -> StartedListener? {
        guard case .ready(let identity) = identityStateProvider.identityState else {
            return nil
        }
        let admission = ConnectionAdmission(clock: clock)
        guard let portStore else {
            let listener = try makeListener(identity: identity, port: port, admission: admission)
            listener.start(queue: .global())
            return StartedListener(listener: listener, admission: admission)
        }
        return try startRememberingPort(identity: identity, admission: admission, portStore: portStore)
    }

    /// Binds the persisted port first and falls back to `port` (OS-assigned) only when that bind
    /// fails, persisting whichever port actually bound so the phone's stored address stays valid.
    private func startRememberingPort(
        identity: SecIdentity,
        admission: ConnectionAdmission,
        portStore: any ListenerPortStore
    ) throws -> StartedListener? {
        if let preferred = portStore.preferredPort.flatMap(NWEndpoint.Port.init(rawValue:)) {
            let listener = try makeListener(identity: identity, port: preferred, admission: admission)
            if case .ready(let bound) = binder.bind(listener) {
                portStore.persist(bound)
                return StartedListener(listener: listener, admission: admission)
            }
            listener.cancel()
        }
        let listener = try makeListener(identity: identity, port: port, admission: admission)
        guard case .ready(let bound) = binder.bind(listener) else {
            listener.cancel()
            throw ListenerBindError.bindFailed
        }
        portStore.persist(bound)
        return StartedListener(listener: listener, admission: admission)
    }

    private func makeListener(
        identity: SecIdentity,
        port: NWEndpoint.Port,
        admission: ConnectionAdmission
    ) throws -> NWListener {
        try listenerFactory.makeListener(identity: identity, port: port, verify: verify, admission: admission)
    }
}

public enum ListenerBindError: Error, Sendable, Equatable {
    case bindFailed
}
