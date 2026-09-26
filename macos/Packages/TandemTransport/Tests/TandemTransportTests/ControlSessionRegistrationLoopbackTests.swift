import Foundation
import Network
import Security
import Testing
import TandemCrypto
import TandemProtocol
@testable import TandemTransport

/// E12-12, finding #5: proves the full session-wiring path -- not just that the raw TLS handshake
/// completes (`VerifyBlockLoopbackTests`) -- by speaking the client half of the protocol (its own
/// `VersionHello`) so the server's `VersionHandshake` actually resolves `.ready` and `wireSession`
/// registers the resulting session. A spy `ControlSessionRegistering` (not `ControlSessionRegistry`'s
/// own private state) observes the registration and the fingerprint it was keyed under.
@Suite("Control session registration (hosted)", .serialized)
struct ControlSessionRegistrationLoopbackTests {

    @Test(.timeLimit(.minutes(1)))
    func verifyBlock_trustedCertReachesProtocolReady_registersSessionUnderClientFingerprint() async throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }
        let clientKeychain = try TemporaryKeychain()
        defer { clientKeychain.cleanup() }

        let clientIdentity = try clientKeychain.makeSecIdentity()
        let clientFingerprint = try Self.fingerprint(for: clientIdentity)

        let spyRegistry = SpyControlSessionRegistry()
        let decisionCorrelator = PeerDecisionCorrelator()
        let verify = Self.makeVerify(trusting: clientFingerprint, decisionCorrelator: decisionCorrelator)
        let listener = try NWListenerFactory(
            sessionRegistry: spyRegistry,
            decisionCorrelator: decisionCorrelator
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

        try await Self.speakClientHalfOfProtocol(over: connection)

        let registration = await spyRegistry.waitForRegistration(timeout: 5)
        #expect(registration?.fingerprint == clientFingerprint)
    }

    /// E14-16's own missing production link: a `.pairingCandidate` connection (unknown
    /// fingerprint, open window, no other candidate in flight) reaching protocol `.ready` is
    /// handed to the configured ``PairingCandidateDriver`` -- and, unlike the `.trusted` case
    /// above, is never registered (registration stays `.trusted`-only, E12-19).
    @Test(.timeLimit(.minutes(1)))
    func verifyBlock_pairingCandidateReachesProtocolReady_handedToDriverNeverRegistered() async throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }
        let clientKeychain = try TemporaryKeychain()
        defer { clientKeychain.cleanup() }

        let clientIdentity = try clientKeychain.makeSecIdentity()
        let clientFingerprint = try Self.fingerprint(for: clientIdentity)

        let spyRegistry = SpyControlSessionRegistry()
        let spyDriver = SpyPairingCandidateDriver()
        let decisionCorrelator = PeerDecisionCorrelator()
        let verify = PeerVerifier.makeVerifyBlock(
            trustStore: FixedTrustStoreReader(fingerprints: []),
            window: FixedPairingWindowState(isOpen: true, candidateInFlight: false),
            onDecision: { metadata, decision, recordedFingerprint, recordedSpkiDer in
                decisionCorrelator.record(
                    metadataIdentifier: ObjectIdentifier(metadata),
                    decision: decision,
                    fingerprint: recordedFingerprint,
                    spkiDer: recordedSpkiDer
                )
            }
        )
        let listener = try NWListenerFactory(
            sessionRegistry: spyRegistry,
            decisionCorrelator: decisionCorrelator,
            pairingCandidateDriver: spyDriver
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

        try await Self.speakClientHalfOfProtocol(over: connection)

        let drive = await spyDriver.waitForDrive(timeout: 5)
        if let drive {
            let observedFingerprint = try SpkiFingerprint.of(spkiDer: drive.handshakeSpkiDer)
            #expect(observedFingerprint == clientFingerprint)
        } else {
            Issue.record("expected the pairing candidate driver to be invoked")
        }

        let registration = await spyRegistry.waitForRegistration(timeout: 0.3)
        #expect(registration == nil)
    }

    // MARK: - Harness

    private static func makeVerify(
        trusting fingerprint: SpkiFingerprint,
        decisionCorrelator: PeerDecisionCorrelator
    ) -> TandemVerifyBlock {
        PeerVerifier.makeVerifyBlock(
            trustStore: FixedTrustStoreReader(fingerprints: [fingerprint]),
            window: FixedPairingWindowState(isOpen: false, candidateInFlight: false),
            onDecision: { metadata, decision, recordedFingerprint, recordedSpkiDer in
                decisionCorrelator.record(
                    metadataIdentifier: ObjectIdentifier(metadata),
                    decision: decision,
                    fingerprint: recordedFingerprint,
                    spkiDer: recordedSpkiDer
                )
            }
        )
    }

    /// A bare TLS-ready connection is never registered (E12-12's session wiring gates registration
    /// on the E12-07 `VersionHandshake` itself resolving `.ready`, both sides) -- so this speaks the
    /// client half of the protocol for real, over the same `NWConnectionByteStreamConnection`/
    /// `ChannelMultiplexer` production types the server uses.
    private static func speakClientHalfOfProtocol(over connection: NWConnection) async throws {
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
            return
        }
    }

    private static func fingerprint(for identity: SecIdentity) throws -> SpkiFingerprint {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        guard status == errSecSuccess, let certificate else {
            throw ControlSessionRegistrationTestError.certificateCopyFailed(status)
        }
        guard let spkiDer = PeerVerifier.spkiDer(fromLeaf: certificate) else {
            throw ControlSessionRegistrationTestError.spkiExtractionFailed
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
                        continuation.resume(throwing: ControlSessionRegistrationTestError.noPort)
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

private enum ControlSessionRegistrationTestError: Error {
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
/// `ListenerLoopbackTests`/`VerifyBlockLoopbackTests`, which each declare their own file-scoped
/// copy) so a `stateUpdateHandler` closure invoked from an arbitrary dispatch queue can safely
/// guard a `CheckedContinuation` against a double-resume.
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

/// `ControlSessionRegistering` spy (E12-12, finding #5): records every `register`/
/// `removeIfCurrent` call it observes, so a test can assert on them without reaching into
/// `ControlSessionRegistry`'s own private state.
private final class SpyControlSessionRegistry: ControlSessionRegistering, @unchecked Sendable {
    struct Registration {
        let fingerprint: SpkiFingerprint
    }

    private enum WaitError: Error {
        case timeout
    }

    private let lock = NSLock()
    private var registration: Registration?
    private var continuation: CheckedContinuation<Registration, Error>?

    func register(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async {
        recordRegistration(Registration(fingerprint: spkiFingerprint))
    }

    func removeIfCurrent(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async {}

    func waitForRegistration(timeout: TimeInterval) async -> Registration? {
        if let existing = existingRegistration() {
            return existing
        }
        return try? await withCheckedThrowingContinuation { continuation in
            self.storeContinuation(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.timeOutPendingContinuation()
            }
        }
    }

    private func recordRegistration(_ value: Registration) {
        lock.lock()
        registration = value
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }

    private func existingRegistration() -> Registration? {
        lock.lock()
        defer { lock.unlock() }
        return registration
    }

    private func storeContinuation(_ continuation: CheckedContinuation<Registration, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    private func timeOutPendingContinuation() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(throwing: WaitError.timeout)
    }
}

/// ``PairingCandidateDriver`` spy: records the one candidate it's ever driven and never touches
/// `session` itself, mirroring ``SpyControlSessionRegistry``'s own wait-with-timeout idiom.
private final class SpyPairingCandidateDriver: PairingCandidateDriver, @unchecked Sendable {
    struct Drive {
        let handshakeSpkiDer: Data
    }

    private enum WaitError: Error {
        case timeout
    }

    private let lock = NSLock()
    private var drive: Drive?
    private var continuation: CheckedContinuation<Drive, Error>?

    func drive(session: any TandemSession, handshakeSpkiDer: Data) async {
        recordDrive(Drive(handshakeSpkiDer: handshakeSpkiDer))
    }

    func waitForDrive(timeout: TimeInterval) async -> Drive? {
        if let existing = existingDrive() {
            return existing
        }
        return try? await withCheckedThrowingContinuation { continuation in
            self.storeContinuation(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.timeOutPendingContinuation()
            }
        }
    }

    private func recordDrive(_ value: Drive) {
        lock.lock()
        drive = value
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }

    private func existingDrive() -> Drive? {
        lock.lock()
        defer { lock.unlock() }
        return drive
    }

    private func storeContinuation(_ continuation: CheckedContinuation<Drive, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    private func timeOutPendingContinuation() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(throwing: WaitError.timeout)
    }
}
