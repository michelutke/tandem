import Foundation
import Network
import Security
import Testing
import TandemCrypto
import TandemProtocol
@testable import TandemTransport

/// E14-16 finding #1: a `.pairingCandidate` connection that never reaches the point of being
/// handed to a ``PairingCandidateDriver`` (an ALPN mismatch, a failed/cancelled handshake, or --
/// exercised here -- a `VersionHello` deadline miss) must still release its window slot and burn
/// one attempt (`docs/planning/decisions.md` D-70), rather than leaving the single candidate slot
/// (D-18) occupied for the rest of the 120 s pairing window.
@Suite("Pairing candidate abandonment (hosted)", .serialized)
struct PairingCandidateAbandonmentLoopbackTests {

    @Test(.timeLimit(.minutes(1)))
    func pairingCandidate_silentAfterTlsNeverSendsHello_slotReleasedAndAttemptBurned() async throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }
        let clientKeychain = try TemporaryKeychain()
        defer { clientKeychain.cleanup() }

        let window = TokenTrackingPairingWindowState(isOpen: true)
        let driver = ReleasingPairingCandidateDriver(window: window)
        let decisionCorrelator = PeerDecisionCorrelator()
        let verify = PeerVerifier.makeVerifyBlock(
            trustStore: FixedTrustStoreReader(fingerprints: []),
            window: window,
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
        let listener = try NWListenerFactory(
            sessionRegistry: ControlSessionRegistry(),
            decisionCorrelator: decisionCorrelator,
            pairingCandidateDriver: driver
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

        let reachedReady = await observer.waitForReady(timeout: 5)
        #expect(reachedReady)

        // Unknown cert, window open, no other candidate in flight: the verify callback admits
        // this connection as `.pairingCandidate` (E12-02). It then goes silent -- never sends its
        // own `VersionHello` -- so the server's 5 s hello deadline (E12-07) must eventually fire,
        // and E14-16 finding #1's fix must release the slot even though `drive()` is never called.
        let released = await window.waitForRelease(timeout: 8)
        #expect(released)
        #expect(!window.candidateInFlight)
        #expect(window.attemptsRemaining == 2)
    }

    // MARK: - Harness

    private static func waitForListenerPort(_ listener: NWListener) async throws -> NWEndpoint.Port {
        let resumeGuard = AbandonmentResumeGuard()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard resumeGuard.tryResume() else { return }
                    guard let port = listener.port else {
                        continuation.resume(throwing: PairingCandidateAbandonmentTestError.noPort)
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

private enum PairingCandidateAbandonmentTestError: Error {
    case noPort
}

private struct FixedTrustStoreReader: TrustStoreReader {
    let fingerprints: Set<SpkiFingerprint>

    func contains(_ fingerprint: SpkiFingerprint) throws -> Bool {
        fingerprints.contains { $0.matches(fingerprint) }
    }
}

/// A ``PairingWindowState`` fake that behaves like a single-attempt-budget tracker (mirroring the
/// real ``PairingWindow``'s D-18/D-70 bookkeeping just enough for this suite's own assertions) and
/// lets a test await its first ``releaseCandidate(_:)`` call.
private final class TokenTrackingPairingWindowState: PairingWindowState, @unchecked Sendable {
    let isOpen: Bool
    private let lock = NSLock()
    private var currentToken: PairingCandidateToken?
    private var attempts = 3
    private var didRelease = false
    private var continuation: CheckedContinuation<Bool, Never>?

    init(isOpen: Bool) {
        self.isOpen = isOpen
    }

    var candidateInFlight: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentToken != nil
    }

    var attemptsRemaining: Int {
        lock.lock()
        defer { lock.unlock() }
        return attempts
    }

    func admitCandidate() -> PairingCandidateToken? {
        lock.lock()
        defer { lock.unlock() }
        guard currentToken == nil else { return nil }
        let token = PairingCandidateToken()
        currentToken = token
        return token
    }

    func releaseCandidate(_ token: PairingCandidateToken) {
        lock.lock()
        guard currentToken == token else {
            lock.unlock()
            return
        }
        currentToken = nil
        attempts -= 1
        didRelease = true
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: true)
    }

    func waitForRelease(timeout: TimeInterval) async -> Bool {
        if alreadyReleased() {
            return true
        }
        return await withCheckedContinuation { continuation in
            self.storeContinuation(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.timeOutPendingContinuation()
            }
        }
    }

    private func alreadyReleased() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return didRelease
    }

    private func storeContinuation(_ continuation: CheckedContinuation<Bool, Never>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    private func timeOutPendingContinuation() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: false)
    }
}

/// ``PairingCandidateDriver`` fake that only ever forwards ``candidateAbandoned(token:)`` to the
/// window under test -- ``drive(session:handshakeSpkiDer:token:)`` is never expected to be called
/// in this suite (the connection never reaches `.ready`), so it's a deliberate no-op.
private final class ReleasingPairingCandidateDriver: PairingCandidateDriver, @unchecked Sendable {
    private let window: TokenTrackingPairingWindowState

    init(window: TokenTrackingPairingWindowState) {
        self.window = window
    }

    func drive(session: any TandemSession, handshakeSpkiDer: Data, token: PairingCandidateToken) async {}

    func candidateAbandoned(token: PairingCandidateToken) async {
        window.releaseCandidate(token)
    }
}

/// Lock-protected "resume this continuation exactly once" latch (duplicated from
/// `ListenerLoopbackTests`, which declares its own file-scoped copy).
private final class AbandonmentResumeGuard: @unchecked Sendable {
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
