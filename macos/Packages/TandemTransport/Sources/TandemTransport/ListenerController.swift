import Foundation
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
    private let preferredBindAttempts: Int
    private let preferredBindRetryDelay: Duration
    private let pause: @Sendable (Duration) -> Void

    public init(
        identityStateProvider: any IdentityStateProvider,
        listenerFactory: any ListenerFactory,
        port: NWEndpoint.Port,
        verify: @escaping TandemVerifyBlock,
        clock: any Clock<Duration> = ContinuousClock(),
        portStore: (any ListenerPortStore)? = nil,
        binder: any ListenerBinder = NWListenerBinder(),
        preferredBindAttempts: Int = 5,
        preferredBindRetryDelay: Duration = .seconds(1),
        pause: @escaping @Sendable (Duration) -> Void = ListenerController.blockingPause
    ) {
        self.identityStateProvider = identityStateProvider
        self.listenerFactory = listenerFactory
        self.port = port
        self.verify = verify
        self.clock = clock
        self.portStore = portStore
        self.binder = binder
        self.preferredBindAttempts = preferredBindAttempts
        self.preferredBindRetryDelay = preferredBindRetryDelay
        self.pause = pause
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

    /// Binds the persisted port first, retrying for a short window because a previous process may
    /// not have released it yet. Falls back to `port` (OS-assigned) only when every attempt fails,
    /// and then leaves the stored port alone so the next launch tries the paired port again; a port
    /// is persisted only when none is stored yet.
    private func startRememberingPort(
        identity: SecIdentity,
        admission: ConnectionAdmission,
        portStore: any ListenerPortStore
    ) throws -> StartedListener? {
        let preferredPort = portStore.preferredPort.flatMap(NWEndpoint.Port.init(rawValue:))
        if let preferredPort,
           let started = bindPreferred(preferredPort, identity: identity, admission: admission) {
            return started
        }
        let listener = try makeListener(identity: identity, port: port, admission: admission)
        guard case .ready(let bound) = binder.bind(listener) else {
            listener.cancel()
            throw ListenerBindError.bindFailed
        }
        if preferredPort == nil { portStore.persist(bound) }
        return StartedListener(listener: listener, admission: admission)
    }

    private func bindPreferred(
        _ preferred: NWEndpoint.Port,
        identity: SecIdentity,
        admission: ConnectionAdmission
    ) -> StartedListener? {
        for attempt in 0..<max(preferredBindAttempts, 1) {
            if attempt > 0 { pause(preferredBindRetryDelay) }
            guard let listener = try? makeListener(identity: identity, port: preferred, admission: admission) else {
                return nil
            }
            if case .ready = binder.bind(listener) {
                return StartedListener(listener: listener, admission: admission)
            }
            listener.cancel()
        }
        return nil
    }

    /// Blocks the calling thread, like ``ListenerBinder/bind(_:)`` itself does.
    public static func blockingPause(_ duration: Duration) {
        let parts = duration.components
        Thread.sleep(forTimeInterval: Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
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
