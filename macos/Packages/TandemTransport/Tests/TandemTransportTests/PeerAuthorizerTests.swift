import CryptoKit
import Foundation
import Testing
import TandemCrypto
@testable import TandemTransport

/// SPEC.md §1's verify-callback pin decision (E12-02), unit-tested as a pure function against
/// fakes -- no Keychain, no TLS handshake. Real conforming types: `TrustStore` (E13-06) and the
/// pairing-window state machine (E14-02).
@Suite("PeerAuthorizer")
struct PeerAuthorizerTests {

    @Test
    func peerAuthorizer_unknownFingerprintWindowClosed_rejected() throws {
        let spki = try Self.makeValidSpkiDer()

        let decision = PeerAuthorizer.decide(
            spki: spki,
            trustStore: FixedTrustStoreReader(fingerprints: []),
            window: FixedPairingWindowState(isOpen: false, candidateInFlight: false)
        )

        #expect(decision == .rejected)
    }

    @Test
    func peerAuthorizer_knownFingerprintAnyWindowState_trusted() throws {
        let spki = try Self.makeValidSpkiDer()
        let fingerprint = try SpkiFingerprint.of(spkiDer: spki)
        let trustStore = FixedTrustStoreReader(fingerprints: [fingerprint])

        for window: any PairingWindowState in [
            FixedPairingWindowState(isOpen: false, candidateInFlight: false),
            FixedPairingWindowState(isOpen: true, candidateInFlight: false),
            FixedPairingWindowState(isOpen: true, candidateInFlight: true)
        ] {
            let decision = PeerAuthorizer.decide(spki: spki, trustStore: trustStore, window: window)
            #expect(decision == .trusted)
        }
    }

    @Test
    func peerAuthorizer_unknownFingerprintWindowOpen_pairingCandidate() throws {
        let spki = try Self.makeValidSpkiDer()

        let decision = PeerAuthorizer.decide(
            spki: spki,
            trustStore: FixedTrustStoreReader(fingerprints: []),
            window: FixedPairingWindowState(isOpen: true, candidateInFlight: false)
        )

        #expect(decision == .pairingCandidate)
    }

    @Test
    func peerAuthorizer_trustStoreLocked_rejected() throws {
        let spki = try Self.makeValidSpkiDer()

        // Window open -- if the read error were ever mapped to "unknown" instead of propagated,
        // this would come back `.pairingCandidate` (or worse, `.trusted`) instead of `.rejected`.
        let decision = PeerAuthorizer.decide(
            spki: spki,
            trustStore: ThrowingTrustStoreReader(),
            window: FixedPairingWindowState(isOpen: true, candidateInFlight: false)
        )

        #expect(decision == .rejected)
    }

    @Test
    func peerAuthorizer_nonP256LeafKey_rejected() {
        let notAConformingSpki = Data(repeating: 0xAB, count: SpkiFingerprint.expectedSpkiDerByteCount)

        let decision = PeerAuthorizer.decide(
            spki: notAConformingSpki,
            trustStore: FixedTrustStoreReader(fingerprints: []),
            window: FixedPairingWindowState(isOpen: true, candidateInFlight: false)
        )

        #expect(decision == .rejected)
    }

    @Test
    func peerAuthorizer_secondUnknownCertWhileCandidateInFlight_rejected() throws {
        let spki = try Self.makeValidSpkiDer()

        let decision = PeerAuthorizer.decide(
            spki: spki,
            trustStore: FixedTrustStoreReader(fingerprints: []),
            window: FixedPairingWindowState(isOpen: true, candidateInFlight: true)
        )

        #expect(decision == .rejected)
    }

    @Test
    func peerAuthorizer_concurrentUnknownCandidates_admitsExactlyOne() throws {
        let spki = try Self.makeValidSpkiDer()
        let trustStore = FixedTrustStoreReader(fingerprints: [])
        let window = FixedPairingWindowState(isOpen: true, candidateInFlight: false)
        let collector = DecisionCollector()
        let iterations = 64

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            collector.record(PeerAuthorizer.decide(spki: spki, trustStore: trustStore, window: window))
        }

        #expect(collector.count(of: .pairingCandidate) == 1)
        #expect(collector.count(of: .rejected) == iterations - 1)
    }

    /// A real, structurally valid uncompressed P-256 SPKI DER: the fixed 26-byte
    /// `SubjectPublicKeyInfo` header (SEQUENCE / AlgorithmIdentifier / BIT STRING) that
    /// ``PeerVerifier`` also uses, followed by a freshly generated key's 65-byte
    /// `x963Representation`.
    private static func makeValidSpkiDer() throws -> Data {
        let header = Data([
            0x30, 0x59, 0x30, 0x13,
            0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
            0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07,
            0x03, 0x42, 0x00
        ])
        let point = P256.Signing.PrivateKey().publicKey.x963Representation
        return header + point
    }
}

private struct FixedTrustStoreReader: TrustStoreReader {
    let fingerprints: Set<SpkiFingerprint>

    func contains(_ fingerprint: SpkiFingerprint) throws -> Bool {
        fingerprints.contains { $0.matches(fingerprint) }
    }
}

private struct ThrowingTrustStoreReader: TrustStoreReader {
    func contains(_ fingerprint: SpkiFingerprint) throws -> Bool {
        throw KeychainError.locked
    }
}

/// A ``PairingWindowState`` fake whose ``admitCandidate()`` is a real atomic test-and-set (`NSLock`),
/// so it can stand in for E14-02's real state machine in a concurrency test -- `candidateInFlight`
/// seeds whether the slot starts out already claimed.
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

/// Thread-safe tally of ``PeerAuthorizationDecision`` values recorded from concurrent callers.
private final class DecisionCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [PeerAuthorizationDecision: Int] = [:]

    func record(_ decision: PeerAuthorizationDecision) {
        lock.lock()
        defer { lock.unlock() }
        counts[decision, default: 0] += 1
    }

    func count(of decision: PeerAuthorizationDecision) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[decision, default: 0]
    }
}
