import Foundation
import Network
import Security
import Testing
import TandemCrypto
import TandemStore
@testable import TandemProtocol
@testable import TandemTransport

/// E14-26 tdd (integration): proves the *real* production composition -- `NWListenerFactory`
/// wired with a live `TrustStore` -- actually consumes a `Revoke` frame on a registered trusted
/// session's `CONTROL` channel and dispatches it to `TandemStore`'s own `RevokeHandler.handle`,
/// not a parallel reimplementation (`HarnessRevokeAwareSessionRegistry`, E14-20, DEBUG-only test
/// harness code). Speaks the client half of the protocol for real (mirrors
/// `ControlSessionRegistrationLoopbackTests`), then sends a real `Revoke` envelope on `CONTROL`
/// once the session is Ready and registered, and asserts -- against the real `ControlSessionRegistry`
/// and a real `TrustStore` over a throwaway on-disk keychain, never the login keychain -- that both
/// the trust record and the registered session are gone within E14-20's own 2 s exit criterion.
@Suite("Control CONTROL revoke consumer (hosted)", .serialized)
struct ControlRevokeConsumerLoopbackTests {

    @Test(.timeLimit(.minutes(1)))
    func appComposition_revokeFrameOnRegisteredSession_trustDeletedAndSessionClosed() async throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }
        let clientKeychain = try TemporaryKeychain()
        defer { clientKeychain.cleanup() }

        let clientIdentity = try clientKeychain.makeSecIdentity()
        let clientFingerprint = try Self.fingerprint(for: clientIdentity)

        let trustStore = TrustStore(keychainStore: serverKeychain.store)
        try trustStore.put(
            PeerRecord(
                fingerprint: clientFingerprint,
                displayName: "Test Phone",
                pairedAt: Date(timeIntervalSince1970: 0),
                lastSeen: Date(timeIntervalSince1970: 0),
                capabilities: []
            )
        )

        let sessionRegistry = ControlSessionRegistry()
        let listener = try Self.makeListener(
            serverIdentity: try serverKeychain.makeSecIdentity(),
            trustStore: trustStore,
            sessionRegistry: sessionRegistry
        )
        defer { listener.cancel() }
        let port = try await Self.waitForListenerPort(listener)

        let observer = ConnectionObserver()
        let connection = Self.makeClientConnection(port: port, identity: clientIdentity, observer: observer)
        defer { connection.cancel() }
        connection.start(queue: .global())

        let reachedReady = await observer.waitForReady(timeout: 5)
        #expect(reachedReady)

        let clientMultiplexer = try await Self.speakClientHalfOfProtocol(over: connection)

        // Wait until the server side has actually registered this session before sending Revoke,
        // exactly as production requires (`RevokeHandler.handle` ignores a pre-Ready Revoke).
        let registeredBeforeRevoke = await Self.waitUntil(maxPolls: 250, pollIntervalMs: 20) {
            await sessionRegistry.session(for: clientFingerprint) != nil
        }
        #expect(registeredBeforeRevoke)

        try await clientMultiplexer.send(.control, payload: .revoke(Tandem_V1_Revoke()))

        // E14-20's own exit criterion: both trust stores lack the peer within 2s. Here, this
        // side's trust store and the registered session both go away.
        let revoked = await Self.waitUntil(maxPolls: 100, pollIntervalMs: 20) {
            let stillTrusted = (try? trustStore.get(clientFingerprint)) ?? nil
            let stillRegistered = await sessionRegistry.session(for: clientFingerprint) != nil
            return stillTrusted == nil && !stillRegistered
        }
        #expect(revoked)
        #expect(try trustStore.get(clientFingerprint) == nil)
        let stillRegistered = await sessionRegistry.session(for: clientFingerprint) != nil
        #expect(!stillRegistered)
    }

    // MARK: - Harness

    private static func makeListener(
        serverIdentity: SecIdentity,
        trustStore: TrustStore,
        sessionRegistry: ControlSessionRegistry
    ) throws -> NWListener {
        let decisionCorrelator = PeerDecisionCorrelator()
        let verify = PeerVerifier.makeVerifyBlock(
            trustStore: TandemTrustStoreReader(trustStore: trustStore),
            window: FixedPairingWindowState(isOpen: false),
            onDecision: { metadata, decision, fingerprint, spkiDer, candidateToken in
                decisionCorrelator.record(
                    metadataIdentifier: ObjectIdentifier(metadata),
                    decision: decision,
                    fingerprint: fingerprint,
                    spkiDer: spkiDer,
                    candidateToken: candidateToken
                )
            }
        )
        return try NWListenerFactory(
            sessionRegistry: sessionRegistry,
            decisionCorrelator: decisionCorrelator,
            trustStore: trustStore
        ).makeListener(
            identity: serverIdentity,
            port: .any,
            verify: verify,
            admission: ConnectionAdmission(clock: ContinuousClock())
        )
    }

    private static func fingerprint(for identity: SecIdentity) throws -> SpkiFingerprint {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        guard status == errSecSuccess, let certificate else {
            throw ControlRevokeConsumerTestError.certificateCopyFailed(status)
        }
        guard let spkiDer = PeerVerifier.spkiDer(fromLeaf: certificate) else {
            throw ControlRevokeConsumerTestError.spkiExtractionFailed
        }
        return try SpkiFingerprint.of(spkiDer: spkiDer)
    }

    /// Speaks the client half of the protocol for real (the same sequence
    /// `ControlSessionRegistrationLoopbackTests` already uses), returning the started client
    /// `ChannelMultiplexer` so this test can send a real `Revoke` envelope over it afterward.
    @discardableResult
    private static func speakClientHalfOfProtocol(over connection: NWConnection) async throws -> ChannelMultiplexer {
        let clientAdapter = NWConnectionByteStreamConnection(connection: connection)
        clientAdapter.reportReady()
        let clientSource = ByteStreamConnectionFrameSource(clientAdapter)
        let clientMultiplexer = ChannelMultiplexer(
            source: clientSource,
            sink: { data in try await clientAdapter.send(data) }
        )
        await clientMultiplexer.start()
        let clientHandshake = VersionHandshake(multiplexer: clientMultiplexer, clock: ContinuousClock())
        await clientHandshake.run()
        guard case .ready = await clientHandshake.session else {
            Issue.record("client-side VersionHandshake did not reach ready: \(await clientHandshake.session)")
            return clientMultiplexer
        }
        return clientMultiplexer
    }

    /// Polls `condition` up to `maxPolls` times, `pollIntervalMs` apart, using
    /// `DispatchQueue.asyncAfter` rather than an unbounded-clock sleep or wall-clock read (banned by the
    /// `injected_clock_only` SwiftLint rule in this package; mirrors this same file's
    /// `ConnectionObserver`/`SpyControlSessionRegistry` continuation-based idiom).
    private static func waitUntil(
        maxPolls: Int,
        pollIntervalMs: Int,
        condition: @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<maxPolls {
            if await condition() { return true }
            await Self.sleepOnGlobalQueue(milliseconds: pollIntervalMs)
        }
        return await condition()
    }

    private static func sleepOnGlobalQueue(milliseconds: Int) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                continuation.resume()
            }
        }
    }

    private static func waitForListenerPort(_ listener: NWListener) async throws -> NWEndpoint.Port {
        let resumeGuard = ResumeGuard()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard resumeGuard.tryResume() else { return }
                    guard let port = listener.port else {
                        continuation.resume(throwing: ControlRevokeConsumerTestError.noPort)
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

private enum ControlRevokeConsumerTestError: Error {
    case noPort
    case certificateCopyFailed(OSStatus)
    case spkiExtractionFailed
}

/// Always-closed pairing window: this test only ever admits the pre-trusted client, never a
/// pairing candidate.
private final class FixedPairingWindowState: PairingWindowState, @unchecked Sendable {
    let isOpen: Bool

    init(isOpen: Bool) {
        self.isOpen = isOpen
    }

    func admitCandidate() -> PairingCandidateToken? { nil }
    func releaseCandidate(_ token: PairingCandidateToken) {}
}

/// Lock-protected "resume this continuation exactly once" latch (duplicated from
/// `ControlSessionRegistrationLoopbackTests`/`ListenerLoopbackTests`/`VerifyBlockLoopbackTests`,
/// which each declare their own file-scoped copy).
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
