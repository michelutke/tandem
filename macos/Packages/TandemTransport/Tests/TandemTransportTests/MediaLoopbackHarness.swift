import Foundation
import Network
import Security
import TandemCrypto
import TandemProtocol
@testable import TandemTransport

/// Real mTLS on localhost with one pinned client identity, file-keychain identities only, for the
/// E60-03 media acceptor integration tests.
final class MediaLoopbackHarness: @unchecked Sendable {
    let registry = ControlSessionRegistry()
    let validator: OneShotTicketValidator
    let acceptor: MediaConnectionAcceptor
    let port: NWEndpoint.Port

    private let listener: NWListener
    private let serverKeychain: TemporaryKeychain
    private let clientKeychain: TemporaryKeychain
    private let clientIdentity: SecIdentity

    init(onBound: @escaping @Sendable () -> Void = {}) async throws {
        serverKeychain = try TemporaryKeychain()
        clientKeychain = try TemporaryKeychain()
        clientIdentity = try clientKeychain.makeSecIdentity()
        let clientFingerprint = try Self.fingerprint(of: clientIdentity)
        validator = OneShotTicketValidator(peer: clientFingerprint)
        acceptor = MediaConnectionAcceptor(validator: validator, clock: ContinuousClock(), onBound: { _ in onBound() })

        let correlator = PeerDecisionCorrelator()
        let verify = PeerVerifier.makeVerifyBlock(
            trustStore: PinnedTrustStore(fingerprint: clientFingerprint),
            window: ClosedPairingWindow(),
            onDecision: { metadata, decision, fingerprint, spkiDer, token in
                correlator.record(
                    metadataIdentifier: ObjectIdentifier(metadata),
                    decision: decision,
                    fingerprint: fingerprint,
                    spkiDer: spkiDer,
                    candidateToken: token
                )
            }
        )
        listener = try NWListenerFactory(
            sessionRegistry: registry,
            decisionCorrelator: correlator,
            mediaConnectionHandler: acceptor
        ).makeListener(
            identity: try serverKeychain.makeSecIdentity(),
            port: .any,
            verify: verify,
            admission: ConnectionAdmission(clock: ContinuousClock())
        )
        port = try await Self.start(listener)
    }

    func cleanup() {
        listener.cancel()
        serverKeychain.cleanup()
        clientKeychain.cleanup()
    }

    /// A ready client connection (second mTLS connection of the same pinned identity).
    func connectClient() async throws -> NWConnectionByteStreamConnection {
        let options = NWProtocolTLS.Options()
        let sec = options.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv13)
        if let secIdentity = sec_identity_create(clientIdentity) {
            sec_protocol_options_set_local_identity(sec, secIdentity)
        }
        sec_protocol_options_add_tls_application_protocol(sec, tandemALPN)
        sec_protocol_options_set_verify_block(sec, { _, _, complete in complete(true) }, .global())
        let connection = NWConnection(
            host: "127.0.0.1",
            port: port,
            using: NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        )
        let observer = ConnectionObserver()
        observer.attach(to: connection)
        connection.start(queue: .global())
        guard await observer.waitForReady(timeout: 5) else { throw HarnessError.clientNotReady }
        let adapter = NWConnectionByteStreamConnection(connection: connection)
        adapter.reportReady()
        return adapter
    }

    /// Completes the client half of the `VersionHello` exchange so the server registers a control session.
    func openControlSession() async throws -> ChannelMultiplexer {
        let client = try await connectClient()
        let multiplexer = ChannelMultiplexer(
            source: ByteStreamConnectionFrameSource(client),
            sink: { data in try await client.send(data) }
        )
        await multiplexer.start()
        let handshake = VersionHandshake(multiplexer: multiplexer, clock: ContinuousClock())
        await handshake.run()
        guard case .ready = await handshake.session else { throw HarnessError.handshakeFailed }
        return multiplexer
    }

    /// Waits for the server to close `client`: orderly EOF or a transport error both count.
    func waitForServerClose(_ client: NWConnectionByteStreamConnection) async -> Bool {
        do {
            for try await _ in client.receive() {}
            return true
        } catch {
            return true
        }
    }

    enum HarnessError: Error {
        case clientNotReady
        case handshakeFailed
        case noPort
        case identityUnreadable
    }

    private static func fingerprint(of identity: SecIdentity) throws -> SpkiFingerprint {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate,
            let spkiDer = PeerVerifier.spkiDer(fromLeaf: certificate)
        else { throw HarnessError.identityUnreadable }
        return try SpkiFingerprint.of(spkiDer: spkiDer)
    }

    private static func start(_ listener: NWListener) async throws -> NWEndpoint.Port {
        try await withCheckedThrowingContinuation { continuation in
            let once = OnceLatch()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard once.claim() else { return }
                    if let port = listener.port {
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: HarnessError.noPort)
                    }
                case .failed(let error):
                    guard once.claim() else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .global())
        }
    }
}

private final class OnceLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

private struct PinnedTrustStore: TrustStoreReader {
    let fingerprint: SpkiFingerprint

    func contains(_ candidate: SpkiFingerprint) throws -> Bool {
        fingerprint.matches(candidate)
    }
}

private struct ClosedPairingWindow: PairingWindowState {
    let isOpen = false

    func admitCandidate() -> PairingCandidateToken? { nil }

    func releaseCandidate(_ token: PairingCandidateToken) {}
}
