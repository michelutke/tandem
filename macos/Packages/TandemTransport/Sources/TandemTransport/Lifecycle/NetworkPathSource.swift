import Network

/// One point-in-time network path snapshot (E20-11, PRD F-3.4, UC-04): the set of currently
/// available interface names, as ``NetworkPathSource`` and ``PathChangeController`` see it.
/// Named interfaces only (`"en0"`, `"utun0"`, ...) -- never an address, matching invariant 3's
/// spirit that no address is ever a trust input in this codebase either.
public struct NetworkPathSnapshot: Sendable, Equatable {
    public var interfaces: Set<String>

    public init(interfaces: Set<String>) {
        self.interfaces = interfaces
    }
}

/// Seam over `NWPathMonitor` (E20-11): ``paths`` never finishes; the production adapter is
/// ``NWPathMonitorSource``, and a scripted fake drives ``PathChangeController`` in tests.
public protocol NetworkPathSource: Sendable {
    var paths: AsyncStream<NetworkPathSnapshot> { get }
}

/// Production ``NetworkPathSource`` over `NWPathMonitor`, watching every interface type (Wi-Fi,
/// wired, `utun` VPN) so a VPN toggle is observed exactly like a Wi-Fi switch (E20-11's
/// description: "Wi-Fi switch, VPN toggle").
public final class NWPathMonitorSource: NetworkPathSource, @unchecked Sendable {

    public let paths: AsyncStream<NetworkPathSnapshot>
    private let continuation: AsyncStream<NetworkPathSnapshot>.Continuation
    private let monitor: NWPathMonitor

    public init(queue: DispatchQueue = .global()) {
        let (paths, continuation) = AsyncStream<NetworkPathSnapshot>.makeStream()
        self.paths = paths
        self.continuation = continuation
        self.monitor = NWPathMonitor()

        monitor.pathUpdateHandler = { path in
            let interfaces = Set(path.availableInterfaces.map(\.name))
            continuation.yield(NetworkPathSnapshot(interfaces: interfaces))
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
        continuation.finish()
    }
}
