import TandemTransport

/// Recording ``SystemPowerEvents`` fake driven directly by ``send(_:)``, standing in for a real
/// `NSWorkspace` notification stream (E20-10). Shared by ``SleepWakeController``'s own tests and
/// E22-08's ``MenuBarViewModel`` tests -- the one seam both observe.
public final class FakeSystemPowerEvents: SystemPowerEvents, @unchecked Sendable {
    public let events: AsyncStream<SystemPowerEvent>
    private let continuation: AsyncStream<SystemPowerEvent>.Continuation

    public init() {
        (events, continuation) = AsyncStream<SystemPowerEvent>.makeStream()
    }

    public func send(_ event: SystemPowerEvent) {
        continuation.yield(event)
    }
}

/// Recording ``NetworkPathSource`` fake driven directly by ``send(_:)``, standing in for a real
/// `NWPathMonitor` path stream (E20-11). Shared by ``PathChangeController``'s own tests and
/// E22-08's ``MenuBarViewModel`` tests -- the one seam both observe.
public final class FakeNetworkPathSource: NetworkPathSource, @unchecked Sendable {
    public let paths: AsyncStream<NetworkPathSnapshot>
    private let continuation: AsyncStream<NetworkPathSnapshot>.Continuation

    public init() {
        (paths, continuation) = AsyncStream<NetworkPathSnapshot>.makeStream()
    }

    public func send(_ snapshot: NetworkPathSnapshot) {
        continuation.yield(snapshot)
    }
}
