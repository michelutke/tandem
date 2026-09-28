import Foundation

/// A ``BonjourPublisher`` conformer's publish attempt failed for a reason worth surfacing to the
/// user. Only the Local Network privacy policy denial is distinguished here (E21-03, fed to
/// `LocalNetworkPermissionViewModel` in TandemApp) -- any other `NetService`/DNS-SD failure (a
/// name collision, a timeout) isn't surfaced this way since nothing reacts to it yet (YAGNI);
/// ``BonjourAdvertiser``'s own next scheduled republish is that case's existing retry.
public enum BonjourPublishError: Sendable, Equatable {
    case policyDenied
}

/// Seam over Bonjour (`_tandem._tcp`) service publication that ``BonjourAdvertiser`` (E21-02)
/// drives: publish (or republish under a new instance name/TXT record) and unpublish. The
/// production adapter is ``NetServiceBonjourPublisher``; a recording fake drives
/// ``BonjourAdvertiser`` in tests.
public protocol BonjourPublisher: Sendable {
    /// Emits ``BonjourPublishError/policyDenied`` whenever a publish attempt fails because the
    /// Local Network privacy permission (E21-03) hasn't been granted.
    var errors: AsyncStream<BonjourPublishError> { get }
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

    /// `kDNSServiceErr_PolicyDenied` (dns_sd.h). `NSNetServicesError` (`NSNetServices.h`) has no
    /// distinct "denied" case -- only `unknownError`/`collisionError`/`notFoundError`/etc -- so this
    /// raw DNS-SD code, if macOS passes it through `didNotPublish`'s error dict verbatim rather
    /// than folding it into `unknownError`, is the only way to tell a Local Network privacy denial
    /// (E21-03) apart from an ordinary collision or timeout. Unverified against a real "fresh
    /// macOS user" denial -- that's exactly this issue's own manual gate,
    /// `freshMacUser_firstAdvertise_localNetworkPromptShownOnce` -- so a manual-gate run that finds
    /// this code wrong (or the error folded into `unknownError`) should correct it here.
    private static let policyDeniedDnsSdErrorCode = -65570

    public nonisolated let errors: AsyncStream<BonjourPublishError>
    private let errorsContinuation: AsyncStream<BonjourPublishError>.Continuation

    private var currentService: NetService?
    private var currentDelegate: PublishDelegate?

    public init() {
        (errors, errorsContinuation) = AsyncStream<BonjourPublishError>.makeStream()
    }

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
        let delegate = PublishDelegate(onPolicyDenied: { [errorsContinuation] in
            errorsContinuation.yield(.policyDenied)
        })
        service.delegate = delegate
        service.schedule(in: .main, forMode: .common)
        service.setTXTRecord(txtRecord)
        service.publish()
        currentService = service
        currentDelegate = delegate
    }

    public func unpublish() async {
        currentService?.stop()
        currentService = nil
        currentDelegate = nil
    }

    /// `NetServiceDelegate` refines `NSObjectProtocol`, which an `actor` can never conform to
    /// itself (it can't subclass `NSObject`) -- this plain `NSObject` bridges `didNotPublish` back
    /// to ``errorsContinuation`` via a plain closure, retained by the owning actor's
    /// ``currentDelegate`` for exactly as long as its `NetService` is (``currentService`` and
    /// ``currentDelegate`` are always replaced together, in ``publish(instanceName:port:txtRecord:)``).
    private final class PublishDelegate: NSObject, NetServiceDelegate {
        private let onPolicyDenied: @Sendable () -> Void

        init(onPolicyDenied: @escaping @Sendable () -> Void) {
            self.onPolicyDenied = onPolicyDenied
        }

        func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
            guard errorDict[NetService.errorCode]?.intValue == NetServiceBonjourPublisher.policyDeniedDnsSdErrorCode
            else { return }
            onPolicyDenied()
        }
    }
}
