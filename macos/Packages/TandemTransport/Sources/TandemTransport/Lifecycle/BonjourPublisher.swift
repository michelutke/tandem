import Foundation

/// Seam over Bonjour (`_tandem._tcp`) service publication that ``BonjourAdvertiser`` (E21-02)
/// drives: publish (or republish under a new instance name/TXT record) and unpublish. The
/// production adapter is ``NetServiceBonjourPublisher``; a recording fake drives
/// ``BonjourAdvertiser`` in tests.
public protocol BonjourPublisher: Sendable {
    func publish(instanceName: String, port: UInt16, txtRecord: Data) async
    func unpublish() async
}

/// Production ``BonjourPublisher`` over `Foundation.NetService`, deliberately not a second
/// `NWListener` (E21-02 design call): `NetService(domain:type:name:port:)` registers Bonjour
/// DNS-SD records (PTR/SRV/TXT) that *reference* an already-open port without itself owning or
/// binding that port -- no new listening socket is created here, so publishing, updating the TXT
/// record, or fully unpublishing/republishing under a new instance name (required daily, since the
/// instance name IS the rotating id, ``BonjourAdvertiser``) can never affect the real
/// control-connection `NWListener` or any of its open connections.
///
/// An `NWListener.Service`-based design was considered and rejected: `NWListener.Service`'s
/// advertised SRV port is always the listener's OWN bound port, so advertising the
/// control-connection's port that way would require attaching the Bonjour service directly to the
/// real TLS-accepting `NWListener` itself, which would then force any Bonjour-name change to go
/// through that listener's own start/stop lifecycle -- directly conflicting with the requirement
/// that a daily id refresh never cancels an open connection.
///
/// An `actor`, not a lock-guarded class: `NetService` is not `Sendable`, and actor isolation is
/// what lets `currentService` be stored and mutated safely without needing `Sendable` on
/// `NetService` itself -- every ``publish(instanceName:port:txtRecord:)``/``unpublish()`` call is
/// already serialized through this actor's own mailbox, so no separate lock is needed.
public actor NetServiceBonjourPublisher: BonjourPublisher {
    private static let serviceType = "_tandem._tcp."
    private static let serviceDomain = ""

    private var currentService: NetService?

    public init() {}

    /// Stops any previously-published service, then creates and publishes a fresh `NetService`
    /// under `instanceName`. `NetService` is scheduled on the main run loop's common mode before
    /// `publish()`: its underlying registration and delegate callbacks are pumped by whichever run
    /// loop it is scheduled on, and this method may be called from a non-run-loop-pumping Swift
    /// concurrency context, so it is scheduled explicitly rather than relying on
    /// `RunLoop.current` at the calling thread.
    public func publish(instanceName: String, port: UInt16, txtRecord: Data) async {
        currentService?.stop()

        let service = NetService(
            domain: Self.serviceDomain, type: Self.serviceType, name: instanceName, port: Int32(port)
        )
        service.schedule(in: .main, forMode: .common)
        service.setTXTRecord(txtRecord)
        service.publish()
        currentService = service
    }

    public func unpublish() async {
        currentService?.stop()
        currentService = nil
    }
}
