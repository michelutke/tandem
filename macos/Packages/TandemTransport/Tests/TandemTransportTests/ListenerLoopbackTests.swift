import Foundation
import Network
import Security
import Testing
import TandemCrypto
import TandemProtocol
@testable import TandemTransport

/// Real `NWListener`/`NWConnection` loopback tests (E12-01), built via `NWListenerFactory` and a
/// real client, using `TemporaryKeychain` (E10-07b, D-75) for identities -- never the login
/// keychain. Every test is bounded by `.timeLimit` plus its own explicit deadlines
/// (`ConnectionObserver`); nothing waits unboundedly. The server's verify block unconditionally
/// accepts (real pin-check logic is E12-02, out of scope here).
@Suite("Listener loopback (hosted)", .serialized)
struct ListenerLoopbackTests {

    @Test(.timeLimit(.minutes(1)))
    func listener_loopbackValidClient_negotiatesTls13AndTandemAlpn() async throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }
        let clientKeychain = try TemporaryKeychain()
        defer { clientKeychain.cleanup() }

        let listener = try Self.makeServerListener(identity: try serverKeychain.makeSecIdentity())
        defer { listener.cancel() }
        let port = try await Self.waitForListenerPort(listener)

        let observer = ConnectionObserver()
        let connection = Self.makeClientConnection(
            port: port,
            identity: try clientKeychain.makeSecIdentity(),
            maxVersion: .TLSv13,
            alpn: .offer(tandemALPN),
            observer: observer
        )
        defer { connection.cancel() }
        connection.start(queue: .global())

        let reachedReady = await observer.waitForReady(timeout: 5)
        #expect(reachedReady)

        let rawMetadata = connection.metadata(definition: NWProtocolTLS.definition)
        let metadata = try #require(rawMetadata as? NWProtocolTLS.Metadata)
        let secMetadata = metadata.securityProtocolMetadata
        #expect(sec_protocol_metadata_get_negotiated_tls_protocol_version(secMetadata) == .TLSv13)
        let negotiated = try #require(sec_protocol_metadata_get_negotiated_protocol(secMetadata))
        #expect(String(cString: negotiated) == tandemALPN)

        // Positive control: a conforming connection must stay open. Without this, a listener that
        // force-cancelled every connection (an inverted/broken ALPN check) would still pass every
        // other test in this suite, since none of them assert a good connection survives.
        let stillOpen = await Self.waitForReceiveEOFOrError(connection, timeout: 1)
        #expect(!stillOpen)
    }

    @Test(.timeLimit(.minutes(1)))
    func listener_loopbackClientMaxTls12_handshakeFailsNoAppBytes() async throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }
        let clientKeychain = try TemporaryKeychain()
        defer { clientKeychain.cleanup() }

        let listener = try Self.makeServerListener(identity: try serverKeychain.makeSecIdentity())
        defer { listener.cancel() }
        let port = try await Self.waitForListenerPort(listener)

        let observer = ConnectionObserver()
        let connection = Self.makeClientConnection(
            port: port,
            identity: try clientKeychain.makeSecIdentity(),
            maxVersion: .TLSv12,
            alpn: .offer(tandemALPN),
            observer: observer
        )
        defer { connection.cancel() }
        connection.start(queue: .global())

        let reachedReady = await observer.waitForReady(timeout: 5)
        #expect(!reachedReady)
    }

    @Test(.timeLimit(.minutes(1)))
    func listener_loopbackClientWithoutCertificate_handshakeFails() async throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }

        let listener = try Self.makeServerListener(identity: try serverKeychain.makeSecIdentity())
        defer { listener.cancel() }
        let port = try await Self.waitForListenerPort(listener)

        let observer = ConnectionObserver()
        let connection = Self.makeClientConnection(
            port: port,
            identity: nil,
            maxVersion: .TLSv13,
            alpn: .offer(tandemALPN),
            observer: observer
        )
        defer { connection.cancel() }
        connection.start(queue: .global())

        // A TLS 1.3 client reaches `.ready` once it has verified the server's own `Finished` --
        // this happens before the server evaluates the client's (here, empty) Certificate
        // message, so `.ready` fires transiently exactly as it does for the "no ALPN offered"
        // case below; the server then aborts once it sees no client certificate satisfying its
        // `peer_authentication_required` requirement, and the client discovers this on its next
        // read attempt (confirmed empirically against this package's `NWListenerFactory`; no
        // application byte ever reaches the listener either way, since it never calls
        // `.receive()` on an accepted connection). `reachedReady` is a Network.framework quirk,
        // not a security requirement: if a future version instead rejects this before `.ready`,
        // that is a strictly stronger outcome, not a regression, so assert the disjunction rather
        // than each half separately -- what must never happen is the connection staying open.
        let reachedReady = await observer.waitForReady(timeout: 5)
        let closed = reachedReady ? await Self.waitForReceiveEOFOrError(connection, timeout: 5) : true
        #expect(!reachedReady || closed)
    }

    @Test(.timeLimit(.minutes(1)))
    func listener_running_exactlyOneListeningTcpSocket() throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }

        let listener = try Self.makeServerListener(identity: try serverKeychain.makeSecIdentity())
        defer { listener.cancel() }

        let ready = Self.waitForListenerReadySync(listener)
        let port = try #require(ready)

        let output = try run(
            "/usr/sbin/lsof",
            ["-a", "-p", String(ProcessInfo.processInfo.processIdentifier), "-iTCP", "-sTCP:LISTEN", "-P", "-n"]
        )
        let listeningLines = output
            .split(separator: "\n")
            .filter { $0.contains("(LISTEN)") }

        #expect(listeningLines.count == 1)
        let portString = String(port.rawValue)
        #expect(listeningLines.allSatisfy { $0.contains(":\(portString) ") || $0.hasSuffix(":\(portString)") })
    }

    @Test(.timeLimit(.minutes(1)), arguments: [AlpnOffer.none, AlpnOffer.offer("other/1")])
    func listener_loopbackClientWithoutTandemAlpn_handshakeFails(alpnOffer: AlpnOffer) async throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }
        let clientKeychain = try TemporaryKeychain()
        defer { clientKeychain.cleanup() }

        let listener = try Self.makeServerListener(identity: try serverKeychain.makeSecIdentity())
        defer { listener.cancel() }
        let port = try await Self.waitForListenerPort(listener)

        let observer = ConnectionObserver()
        let connection = Self.makeClientConnection(
            port: port,
            identity: try clientKeychain.makeSecIdentity(),
            maxVersion: .TLSv13,
            alpn: alpnOffer,
            observer: observer
        )
        defer { connection.cancel() }
        connection.start(queue: .global())

        switch alpnOffer {
        case .none:
            // Gotcha 6: Network.framework accepts a missing ALPN offer, so this reaches `.ready`
            // transiently; the listener's own explicit post-ready ALPN check then force-cancels
            // it (docs/protocol/SPEC.md, "Platform implementation notes"). `NWConnection` does not
            // proactively surface a peer-initiated close via `stateUpdateHandler` alone while no
            // read is outstanding, so detect it the way a real caller would: attempt a `.receive()`
            // and observe the resulting EOF/error. `reachedReady` is a Network.framework quirk,
            // not a security requirement -- see the disjunction rationale on the "no certificate"
            // test above.
            let reachedReady = await observer.waitForReady(timeout: 5)
            let closed = reachedReady ? await Self.waitForReceiveEOFOrError(connection, timeout: 5) : true
            #expect(!reachedReady || closed)
        case .offer:
            // A mismatched ALPN offer is rejected by the TLS stack itself, before `.ready`.
            let reachedReady = await observer.waitForReady(timeout: 5)
            #expect(!reachedReady)
        }
    }

    // MARK: - Harness

    private static func makeServerListener(identity: SecIdentity) throws -> NWListener {
        try NWListenerFactory(sessionRegistry: ControlSessionRegistry(), decisionCorrelator: PeerDecisionCorrelator()).makeListener(
            identity: identity,
            port: .any,
            verify: { _, _, complete in complete(true) },
            admission: ConnectionAdmission(clock: ContinuousClock())
        )
    }

    private static func waitForListenerPort(_ listener: NWListener) async throws -> NWEndpoint.Port {
        let resumeGuard = ResumeGuard()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard resumeGuard.tryResume() else { return }
                    guard let port = listener.port else {
                        continuation.resume(throwing: ListenerLoopbackTestError.noPort)
                        return
                    }
                    continuation.resume(returning: port)
                case .failed(let error):
                    guard resumeGuard.tryResume() else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .global())
        }
    }

    /// Synchronous variant for the non-`async` `exactlyOneListeningTcpSocket` test: blocks on a
    /// semaphore with a bounded deadline rather than `Task.sleep` (banned in this package).
    private static func waitForListenerReadySync(_ listener: NWListener) -> NWEndpoint.Port? {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = PortBox()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                resultBox.set(listener.port)
                semaphore.signal()
            case .failed:
                semaphore.signal()
            default:
                break
            }
        }
        listener.start(queue: .global())
        _ = semaphore.wait(timeout: .now() + 5)
        return resultBox.get()
    }

    /// Issues a single `.receive()` and resolves `true` if it completes with EOF or an error
    /// (the server closed/reset the connection) before `timeout` elapses, `false` otherwise. Used
    /// to detect a peer-initiated close that `stateUpdateHandler` alone does not surface while no
    /// read is outstanding.
    private static func waitForReceiveEOFOrError(_ connection: NWConnection, timeout: TimeInterval) async -> Bool {
        let resumeGuard = ResumeGuard()
        return await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, isComplete, error in
                guard resumeGuard.tryResume() else { return }
                continuation.resume(returning: isComplete || error != nil)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard resumeGuard.tryResume() else { return }
                continuation.resume(returning: false)
            }
        }
    }

    private static func makeClientConnection(
        port: NWEndpoint.Port,
        identity: SecIdentity?,
        maxVersion: tls_protocol_version_t,
        alpn: AlpnOffer,
        observer: ConnectionObserver
    ) -> NWConnection {
        let options = NWProtocolTLS.Options()
        let sec = options.securityProtocolOptions

        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(sec, maxVersion)

        if let identity, let secIdentity = sec_identity_create(identity) {
            sec_protocol_options_set_local_identity(sec, secIdentity)
        }

        switch alpn {
        case .none:
            break
        case .offer(let value):
            sec_protocol_options_add_tls_application_protocol(sec, value)
        }

        sec_protocol_options_set_verify_block(sec, { _, _, complete in complete(true) }, .global())

        let parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(host: "127.0.0.1", port: port, using: parameters)
        observer.attach(to: connection)
        return connection
    }
}

enum AlpnOffer: Sendable, CustomStringConvertible {
    case none
    case offer(String)

    var description: String {
        switch self {
        case .none: return "none"
        case .offer(let value): return "offer(\(value))"
        }
    }
}

enum ListenerLoopbackTestError: Error {
    case noPort
}

/// Lock-protected "resume this continuation exactly once" latch, so a `stateUpdateHandler`
/// closure invoked from an arbitrary dispatch queue can safely guard a `CheckedContinuation`
/// against a double-resume without capturing a plain `var` across a `@Sendable` closure boundary.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }
}

/// Lock-protected box for handing a `NWEndpoint.Port` out of a `stateUpdateHandler` closure to
/// the synchronous caller blocked on the paired semaphore.
private final class PortBox: @unchecked Sendable {
    private let lock = NSLock()
    private var port: NWEndpoint.Port?

    func set(_ value: NWEndpoint.Port?) {
        lock.lock()
        port = value
        lock.unlock()
    }

    func get() -> NWEndpoint.Port? {
        lock.lock()
        defer { lock.unlock() }
        return port
    }
}
