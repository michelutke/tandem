import Foundation
import Network
import Security
import Testing
import TandemCrypto
import TandemProtocol
@testable import TandemTransport

/// SPEC.md §1's verify-callback pin decision, exercised over a real loopback TLS handshake
/// (E12-02) via `PeerVerifier.makeVerifyBlock`. The pure decision logic itself
/// (``PeerAuthorizer``) is unit-tested in `PeerAuthorizerTests`; this suite only proves the glue
/// -- extracting the peer's leaf SPKI from a real `sec_trust_t` -- wires correctly into a real
/// `NWListener`, using `TemporaryKeychain` (E10-07b, D-75) identities, never the login keychain.
@Suite("Verify block (hosted)", .serialized)
struct VerifyBlockLoopbackTests {

    @Test(.timeLimit(.minutes(1)))
    func verifyBlock_loopbackUnknownCertNoWindow_handshakeFailsZeroAppBytes() async throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }
        let clientKeychain = try TemporaryKeychain()
        defer { clientKeychain.cleanup() }

        let verify = PeerVerifier.makeVerifyBlock(
            trustStore: FixedTrustStoreReader(fingerprints: []),
            window: FixedPairingWindowState(isOpen: false, candidateInFlight: false)
        )
        let listener = try NWListenerFactory(
     sessionRegistry: ControlSessionRegistry(),
     decisionCorrelator: PeerDecisionCorrelator()
 ).makeListener(
            identity: try serverKeychain.makeSecIdentity(),
            port: .any,
            verify: verify,
            admission: ConnectionAdmission(clock: ContinuousClock())
        )
        defer { listener.cancel() }
        let port = try await Self.waitForListenerPort(listener)

        let observer = ConnectionObserver()
        let connection = Self.makeClientConnection(
            port: port,
            identity: try clientKeychain.makeSecIdentity(),
            observer: observer
        )
        defer { connection.cancel() }
        connection.start(queue: .global())

        // Unknown fingerprint, no pairing window open: `PeerAuthorizer` returns `.rejected`. As
        // with the "no client certificate" case in `ListenerLoopbackTests` (gotcha 5,
        // `docs/spikes/nwlistener-mtls.md`), the client can reach `.ready` transiently -- it has
        // already verified the server's own `Finished` -- before discovering, on its next read,
        // that the server rejected its certificate inside the verify block and closed. What must
        // never happen is the connection staying open, so assert that disjunction rather than
        // `!reachedReady` alone.
        let reachedReady = await observer.waitForReady(timeout: 5)
        let closed = reachedReady ? await Self.waitForReceiveEOFOrError(connection, timeout: 5) : true
        #expect(!reachedReady || closed)
    }

    @Test(.timeLimit(.minutes(1)))
    func verifyBlock_loopbackTrustedCert_handshakeCompletes() async throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }
        let clientKeychain = try TemporaryKeychain()
        defer { clientKeychain.cleanup() }

        let clientIdentity = try clientKeychain.makeSecIdentity()
        let clientFingerprint = try Self.fingerprint(for: clientIdentity)

        let verify = PeerVerifier.makeVerifyBlock(
            trustStore: FixedTrustStoreReader(fingerprints: [clientFingerprint]),
            window: FixedPairingWindowState(isOpen: false, candidateInFlight: false)
        )
        let listener = try NWListenerFactory(
     sessionRegistry: ControlSessionRegistry(),
     decisionCorrelator: PeerDecisionCorrelator()
 ).makeListener(
            identity: try serverKeychain.makeSecIdentity(),
            port: .any,
            verify: verify,
            admission: ConnectionAdmission(clock: ContinuousClock())
        )
        defer { listener.cancel() }
        let port = try await Self.waitForListenerPort(listener)

        let observer = ConnectionObserver()
        let connection = Self.makeClientConnection(port: port, identity: clientIdentity, observer: observer)
        defer { connection.cancel() }
        connection.start(queue: .global())

        let reachedReady = await observer.waitForReady(timeout: 5)
        #expect(reachedReady)
    }

    @Test(.timeLimit(.minutes(1)))
    func peerAuthorizer_extraChainCertificates_onlyLeafPinned() async throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }
        let clientKeychain = try TemporaryKeychain()
        defer { clientKeychain.cleanup() }
        let extraKeychain = try TemporaryKeychain()
        defer { extraKeychain.cleanup() }

        let clientIdentity = try clientKeychain.makeSecIdentity()
        let clientFingerprint = try Self.fingerprint(for: clientIdentity)
        let extraIdentity = try extraKeychain.makeSecIdentity()
        let extraFingerprint = try Self.fingerprint(for: extraIdentity)
        let extraCertificate = try Self.certificate(for: extraIdentity)

        // Leaf pinned, an unknown extra certificate riding along in the chain: MUST succeed --
        // only the leaf (chain index 0) is ever compared against the trust store, so the extra
        // certificate's own (non-)trust status is irrelevant.
        let (leafPinnedReady, leafPinnedConnection) = try await Self.attemptHandshake(
            serverKeychain: serverKeychain,
            clientIdentity: clientIdentity,
            extraCertificate: extraCertificate,
            trustStore: FixedTrustStoreReader(fingerprints: [clientFingerprint])
        )
        defer { leafPinnedConnection.cancel() }
        #expect(leafPinnedReady)

        // Only the extra certificate pinned, the leaf itself unknown: MUST fail -- pinning the
        // extra certificate must never substitute for pinning the leaf.
        let (extraPinnedReady, extraPinnedConnection) = try await Self.attemptHandshake(
            serverKeychain: serverKeychain,
            clientIdentity: clientIdentity,
            extraCertificate: extraCertificate,
            trustStore: FixedTrustStoreReader(fingerprints: [extraFingerprint])
        )
        defer { extraPinnedConnection.cancel() }
        // As with the "no client certificate" case (gotcha 5, `docs/spikes/nwlistener-mtls.md`),
        // the client can reach `.ready` transiently before discovering, on its next read, that the
        // server rejected its certificate and closed -- assert that disjunction rather than
        // `!extraPinnedReady` alone.
        let extraPinnedClosed = extraPinnedReady
            ? await Self.waitForReceiveEOFOrError(extraPinnedConnection, timeout: 5)
            : true
        #expect(!extraPinnedReady || extraPinnedClosed)
    }

    // MARK: - Harness

    private static func attemptHandshake(
        serverKeychain: TemporaryKeychain,
        clientIdentity: SecIdentity,
        extraCertificate: SecCertificate,
        trustStore: FixedTrustStoreReader
    ) async throws -> (reachedReady: Bool, connection: NWConnection) {
        let verify = PeerVerifier.makeVerifyBlock(
            trustStore: trustStore,
            window: FixedPairingWindowState(isOpen: false, candidateInFlight: false)
        )
        let listener = try NWListenerFactory(
     sessionRegistry: ControlSessionRegistry(),
     decisionCorrelator: PeerDecisionCorrelator()
 ).makeListener(
            identity: try serverKeychain.makeSecIdentity(),
            port: .any,
            verify: verify,
            admission: ConnectionAdmission(clock: ContinuousClock())
        )
        defer { listener.cancel() }
        let port = try await Self.waitForListenerPort(listener)

        let observer = ConnectionObserver()
        let connection = Self.makeClientConnectionWithExtraChainCertificate(
            port: port,
            identity: clientIdentity,
            extraCertificate: extraCertificate,
            observer: observer
        )
        connection.start(queue: DispatchQueue.global())

        let reachedReady = await observer.waitForReady(timeout: 5)
        return (reachedReady, connection)
    }

    private static func certificate(for identity: SecIdentity) throws -> SecCertificate {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        guard status == errSecSuccess, let certificate else {
            throw VerifyBlockLoopbackTestError.certificateCopyFailed(status)
        }
        return certificate
    }

    private static func makeClientConnectionWithExtraChainCertificate(
        port: NWEndpoint.Port,
        identity: SecIdentity,
        extraCertificate: SecCertificate,
        observer: ConnectionObserver
    ) -> NWConnection {
        let options = NWProtocolTLS.Options()
        let sec = options.securityProtocolOptions

        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv13)
        if let secIdentity = sec_identity_create_with_certificates(identity, [extraCertificate] as CFArray) {
            sec_protocol_options_set_local_identity(sec, secIdentity)
        }
        sec_protocol_options_add_tls_application_protocol(sec, tandemALPN)
        sec_protocol_options_set_verify_block(sec, { _, _, complete in complete(true) }, .global())

        let parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(host: "127.0.0.1", port: port, using: parameters)
        observer.attach(to: connection)
        return connection
    }

    private static func fingerprint(for identity: SecIdentity) throws -> SpkiFingerprint {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        guard status == errSecSuccess, let certificate else {
            throw VerifyBlockLoopbackTestError.certificateCopyFailed(status)
        }
        guard let spkiDer = PeerVerifier.spkiDer(fromLeaf: certificate) else {
            throw VerifyBlockLoopbackTestError.spkiExtractionFailed
        }
        return try SpkiFingerprint.of(spkiDer: spkiDer)
    }

    private static func waitForListenerPort(_ listener: NWListener) async throws -> NWEndpoint.Port {
        let resumeGuard = ResumeGuard()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard resumeGuard.tryResume() else { return }
                    guard let port = listener.port else {
                        continuation.resume(throwing: VerifyBlockLoopbackTestError.noPort)
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

    /// Issues a single `.receive()` and resolves `true` if it completes with EOF or an error
    /// (the server closed/reset the connection) before `timeout` elapses, `false` otherwise --
    /// duplicated from `ListenerLoopbackTests`, which declares its own file-scoped copy.
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
        identity: SecIdentity,
        observer: ConnectionObserver
    ) -> NWConnection {
        let options = NWProtocolTLS.Options()
        let sec = options.securityProtocolOptions

        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv13)
        if let secIdentity = sec_identity_create(identity) {
            sec_protocol_options_set_local_identity(sec, secIdentity)
        }
        sec_protocol_options_add_tls_application_protocol(sec, tandemALPN)
        sec_protocol_options_set_verify_block(sec, { _, _, complete in complete(true) }, .global())

        let parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(host: "127.0.0.1", port: port, using: parameters)
        observer.attach(to: connection)
        return connection
    }
}

private enum VerifyBlockLoopbackTestError: Error {
    case noPort
    case certificateCopyFailed(OSStatus)
    case spkiExtractionFailed
}

private struct FixedTrustStoreReader: TrustStoreReader {
    let fingerprints: Set<SpkiFingerprint>

    func contains(_ fingerprint: SpkiFingerprint) throws -> Bool {
        fingerprints.contains { $0.matches(fingerprint) }
    }
}

private final class FixedPairingWindowState: PairingWindowState, @unchecked Sendable {
    let isOpen: Bool
    private let lock = NSLock()
    private var claimed: Bool

    init(isOpen: Bool, candidateInFlight: Bool) {
        self.isOpen = isOpen
        self.claimed = candidateInFlight
    }

    func admitCandidate() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }

    func releaseCandidate() {
        lock.lock()
        defer { lock.unlock() }
        claimed = false
    }
}

/// Lock-protected "resume this continuation exactly once" latch (duplicated from
/// `ListenerLoopbackTests`, which declares its own file-scoped copy) so a `stateUpdateHandler`
/// closure invoked from an arbitrary dispatch queue can safely guard a `CheckedContinuation`
/// against a double-resume.
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
