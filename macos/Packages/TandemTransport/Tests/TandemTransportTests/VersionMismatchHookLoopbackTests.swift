import Foundation
import Network
import Security
import Testing
import TandemCrypto
@testable import TandemProtocol
@testable import TandemTransport

/// E15-16 tdd (integration): a `.trusted` peer that completes real mTLS and then sends a
/// `VersionHello` with an unsupported major is never registered, but its session still reaches
/// `onSessionRegistered` with a state stream ending in `.failed(.versionMismatch)` -- the seam the
/// Mac's menu bar and error banner observe through `ConnectionStateRelay`.
@Suite("Version mismatch session hook (hosted)", .serialized)
struct VersionMismatchHookLoopbackTests {

    @Test(.timeLimit(.minutes(1)))
    func listener_trustedPeerUnsupportedMajor_notRegisteredButHookSeesVersionMismatch() async throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }
        let clientKeychain = try TemporaryKeychain()
        defer { clientKeychain.cleanup() }

        let clientIdentity = try clientKeychain.makeSecIdentity()
        let clientFingerprint = try Self.fingerprint(for: clientIdentity)

        let registry = RecordingRegistry()
        let hooked = HookedSessionBox()
        let decisionCorrelator = PeerDecisionCorrelator()
        let verify = PeerVerifier.makeVerifyBlock(
            trustStore: SingleFingerprintReader(fingerprint: clientFingerprint),
            window: ClosedPairingWindow(),
            onDecision: { metadata, decision, recordedFingerprint, recordedSpkiDer, candidateToken in
                decisionCorrelator.record(
                    metadataIdentifier: ObjectIdentifier(metadata),
                    decision: decision,
                    fingerprint: recordedFingerprint,
                    spkiDer: recordedSpkiDer,
                    candidateToken: candidateToken
                )
            }
        )
        let listener = try NWListenerFactory(
            sessionRegistry: registry,
            decisionCorrelator: decisionCorrelator,
            onSessionRegistered: { fingerprint, session in hooked.record(fingerprint, session) }
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
        #expect(await observer.waitForReady(timeout: 5))

        try await Self.sendUnsupportedMajorHello(over: connection)

        let record = await hooked.waitForRecord(timeout: 5)
        #expect(record?.fingerprint == clientFingerprint)
        guard let session = record?.session else { return }
        var finalState: ConnectionStateMachine.ConnectionState?
        for await state in session.state {
            finalState = state
            if case .failed = state { break }
        }
        #expect(finalState == .failed(.versionMismatch))
        #expect(registry.registrationCount == 0)
    }

    private static func sendUnsupportedMajorHello(over connection: NWConnection) async throws {
        let clientAdapter = NWConnectionByteStreamConnection(connection: connection)
        clientAdapter.reportReady()
        var hello = Tandem_V1_VersionHello()
        hello.major = 99
        var envelope = Tandem_V1_Envelope()
        envelope.channel = .control
        envelope.seq = 1
        envelope.payload = .versionHello(hello)
        try await clientAdapter.send(try FrameEncoder.encode(envelope))
    }

    private static func fingerprint(for identity: SecIdentity) throws -> SpkiFingerprint {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        guard status == errSecSuccess, let certificate,
              let spkiDer = PeerVerifier.spkiDer(fromLeaf: certificate) else {
            throw VersionMismatchHookTestError.identityUnreadable(status)
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
                        continuation.resume(throwing: VersionMismatchHookTestError.noPort)
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
        let connection = NWConnection(
            host: "127.0.0.1",
            port: port,
            using: NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        )
        observer.attach(to: connection)
        return connection
    }
}

private enum VersionMismatchHookTestError: Error {
    case noPort
    case identityUnreadable(OSStatus)
}

private struct SingleFingerprintReader: TrustStoreReader {
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

private final class RecordingRegistry: ControlSessionRegistering, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var registrationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func register(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async {
        lock.withLock { count += 1 }
    }

    func removeIfCurrent(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async {}
}

/// Captures the one `(fingerprint, session)` pair `onSessionRegistered` is called with; the wait
/// is continuation-based with a `DispatchQueue.asyncAfter` timeout (`Task.sleep` is banned here by
/// `injected_clock_only`).
private final class HookedSessionBox: @unchecked Sendable {
    struct Record {
        let fingerprint: SpkiFingerprint
        let session: any TandemSession
    }

    private let lock = NSLock()
    private var recorded: Record?
    private var continuation: CheckedContinuation<Record?, Never>?

    func record(_ fingerprint: SpkiFingerprint, _ session: any TandemSession) {
        lock.lock()
        recorded = Record(fingerprint: fingerprint, session: session)
        let pending = continuation
        continuation = nil
        let value = recorded
        lock.unlock()
        pending?.resume(returning: value)
    }

    func waitForRecord(timeout: TimeInterval) async -> Record? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let recorded {
                lock.unlock()
                continuation.resume(returning: recorded)
                return
            }
            self.continuation = continuation
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.timeOut()
            }
        }
    }

    private func timeOut() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: nil)
    }
}

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
