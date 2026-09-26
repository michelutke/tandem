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

    public init(
        identityStateProvider: any IdentityStateProvider,
        listenerFactory: any ListenerFactory,
        port: NWEndpoint.Port,
        verify: @escaping TandemVerifyBlock,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.identityStateProvider = identityStateProvider
        self.listenerFactory = listenerFactory
        self.port = port
        self.verify = verify
        self.clock = clock
    }

    /// Starts the listener if, and only if, the identity is ready. Returns `nil` (never invoking
    /// ``ListenerFactory``) when the identity is `.missing` or `.error`. Each call builds a fresh
    /// ``ConnectionAdmission`` (E12-18), so a restarted listener starts with a clean pre-auth
    /// budget and throttle state.
    @discardableResult
    public func start() throws -> NWListener? {
        guard case .ready(let identity) = identityStateProvider.identityState else {
            return nil
        }
        let admission = ConnectionAdmission(clock: clock)
        let listener = try listenerFactory.makeListener(
            identity: identity,
            port: port,
            verify: verify,
            admission: admission
        )
        listener.start(queue: .global())
        return listener
    }
}
