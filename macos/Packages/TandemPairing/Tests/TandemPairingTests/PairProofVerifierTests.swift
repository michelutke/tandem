import CryptoKit
import Foundation
import Testing
import TandemCrypto
import TandemTestSupport
import TandemTransport
@testable import TandemPairing

/// The real ``PairRequestVerifier`` (E14-07, `docs/protocol/SPEC.md` §2 "Proof computation"):
/// recomputes `proof` from the handshake-observed phone SPKI and compares in constant time.
@Suite("PairProofVerifier")
struct PairProofVerifierTests {

    @Test
    func verifyProof_validForHandshakeCertSpki_accepted() throws {
        let macSpkiDer = try Self.makeValidSpkiDer()
        let phoneSpkiDer = try Self.makeValidSpkiDer()
        let secret = Data(repeating: 0x11, count: 16)
        let challenge = Data(repeating: 0x22, count: 32)
        let proof = try PairingProof.compute(
            secret: secret, macSpkiDer: macSpkiDer, phoneSpkiDer: phoneSpkiDer, channelBinding: challenge
        )

        let verifier = PairProofVerifier(
            macSpkiDerProvider: { macSpkiDer },
            handshakeSpkiDerProvider: { phoneSpkiDer },
            connectionDecisionProvider: { .pairingCandidate }
        )

        #expect(verifier.verify(proof: proof, secret: secret, challenge: challenge))
    }

    @Test
    func verifyProof_proofForDeviceInfoClaimedKey_rejected() throws {
        let macSpkiDer = try Self.makeValidSpkiDer()
        let actualHandshakeSpkiDer = try Self.makeValidSpkiDer()
        let deviceInfoClaimedSpkiDer = try Self.makeValidSpkiDer()
        let secret = Data(repeating: 0x11, count: 16)
        let challenge = Data(repeating: 0x22, count: 32)

        // A proof computed against the key `deviceInfo` claims -- never the key actually
        // presented on this handshake.
        let proof = try PairingProof.compute(
            secret: secret, macSpkiDer: macSpkiDer, phoneSpkiDer: deviceInfoClaimedSpkiDer, channelBinding: challenge
        )

        let verifier = PairProofVerifier(
            macSpkiDerProvider: { macSpkiDer },
            handshakeSpkiDerProvider: { actualHandshakeSpkiDer },
            connectionDecisionProvider: { .pairingCandidate }
        )

        #expect(!verifier.verify(proof: proof, secret: secret, challenge: challenge))
    }

    @Test
    func verifyProof_wrongSecret_rejected() throws {
        let macSpkiDer = try Self.makeValidSpkiDer()
        let phoneSpkiDer = try Self.makeValidSpkiDer()
        let secret = Data(repeating: 0x11, count: 16)
        let wrongSecret = Data(repeating: 0x33, count: 16)
        let challenge = Data(repeating: 0x22, count: 32)
        let proof = try PairingProof.compute(
            secret: secret, macSpkiDer: macSpkiDer, phoneSpkiDer: phoneSpkiDer, channelBinding: challenge
        )

        let verifier = PairProofVerifier(
            macSpkiDerProvider: { macSpkiDer },
            handshakeSpkiDerProvider: { phoneSpkiDer },
            connectionDecisionProvider: { .pairingCandidate }
        )

        #expect(!verifier.verify(proof: proof, secret: wrongSecret, challenge: challenge))
    }

    @Test
    func verifyProof_comparison_invokesConstantTimeComparatorOnce() throws {
        let macSpkiDer = try Self.makeValidSpkiDer()
        let phoneSpkiDer = try Self.makeValidSpkiDer()
        let secret = Data(repeating: 0x11, count: 16)
        let challenge = Data(repeating: 0x22, count: 32)
        let comparator = SpyByteComparator(result: true)

        let verifier = PairProofVerifier(
            macSpkiDerProvider: { macSpkiDer },
            handshakeSpkiDerProvider: { phoneSpkiDer },
            connectionDecisionProvider: { .pairingCandidate },
            comparator: comparator
        )

        _ = verifier.verify(proof: Data(repeating: 0xFF, count: 32), secret: secret, challenge: challenge)

        #expect(comparator.callCount == 1)
    }

    @Test
    func verifyProof_trustedConnection_rejectedWithoutComputing() throws {
        let comparator = SpyByteComparator(result: true)
        let macSpkiDerProviderCalled = LockedBox(false)
        let handshakeSpkiDerProviderCalled = LockedBox(false)

        let verifier = PairProofVerifier(
            macSpkiDerProvider: {
                macSpkiDerProviderCalled.value = true
                return Data()
            },
            handshakeSpkiDerProvider: {
                handshakeSpkiDerProviderCalled.value = true
                return Data()
            },
            connectionDecisionProvider: { .trusted },
            comparator: comparator
        )

        let outcome = verifier.verify(
            proof: Data(repeating: 0xFF, count: 32),
            secret: Data(repeating: 0x11, count: 16),
            challenge: Data(repeating: 0x22, count: 32)
        )

        #expect(!outcome)
        #expect(comparator.callCount == 0)
        #expect(!macSpkiDerProviderCalled.value)
        #expect(!handshakeSpkiDerProviderCalled.value)
    }

    @Test
    func verifyProof_otherCandidatesPairChallenge_rejected() throws {
        let macSpkiDer = try Self.makeValidSpkiDer()
        let phoneSpkiDer = try Self.makeValidSpkiDer()
        let secret = Data(repeating: 0x11, count: 16)
        let thisCandidatesChallenge = Data(repeating: 0x22, count: 32)
        let otherCandidatesChallenge = Data(repeating: 0x44, count: 32)

        // Same keys and secret, but computed against a different candidate's PairChallenge.
        let proof = try PairingProof.compute(
            secret: secret, macSpkiDer: macSpkiDer, phoneSpkiDer: phoneSpkiDer, channelBinding: otherCandidatesChallenge
        )

        let verifier = PairProofVerifier(
            macSpkiDerProvider: { macSpkiDer },
            handshakeSpkiDerProvider: { phoneSpkiDer },
            connectionDecisionProvider: { .pairingCandidate }
        )

        #expect(!verifier.verify(proof: proof, secret: secret, challenge: thisCandidatesChallenge))
    }

    @Test
    func pairProofVerifier_everyProofVector_matchesExpectedValidity() throws {
        let manifest = try PairingProofVectorFixture.load()
        let proofEntries = manifest.vectors.filter { $0.input.kind == "proof" }
        #expect(!proofEntries.isEmpty)

        for entry in proofEntries {
            let secret = try PairingProofVectorFixture.secret(for: entry)
            let macSpkiDer = try PairingProofVectorFixture.macSpkiDer(for: entry)
            let phoneSpkiDer = try PairingProofVectorFixture.phoneSpkiDer(for: entry)
            let channelBinding = try PairingProofVectorFixture.channelBinding(for: entry)
            let proof = try PairingProofVectorFixture.proof(for: entry)

            let verifier = PairProofVerifier(
                macSpkiDerProvider: { macSpkiDer },
                handshakeSpkiDerProvider: { phoneSpkiDer },
                connectionDecisionProvider: { .pairingCandidate }
            )

            let result = verifier.verify(proof: proof, secret: secret, challenge: channelBinding)
            #expect(result == (entry.expectedError == nil), "vector \(entry.id)")
        }
    }

    @Test
    func pairingWindow_wiredWithRealPairProofVerifier_acceptsCorrectProofRejectsWrongOne() throws {
        let macSpkiDer = try Self.makeValidSpkiDer()
        let phoneSpkiDer = try Self.makeValidSpkiDer()
        let secret = Data(repeating: 0x11, count: 16)

        // Simulates the connection-lifecycle wiring: `PeerVerifier` (E12-02) would set these as
        // the candidate slot is claimed/freed, and clear `decision` once the connection is no
        // longer this window's candidate.
        let decision = LockedBox<PeerAuthorizationDecision>(.pairingCandidate)
        let verifier = PairProofVerifier(
            macSpkiDerProvider: { macSpkiDer },
            handshakeSpkiDerProvider: { phoneSpkiDer },
            connectionDecisionProvider: { decision.value }
        )
        let window = PairingWindow(
            dateProvider: FixedDateProvider(clock: ManualTestClock()).provider,
            proofVerifier: verifier
        )

        window.open(secret: secret)
        let firstToken = try #require(window.admitCandidate())
        let challenge = try #require(window.candidateHellosCompleted(firstToken))

        let wrongProof = Data(repeating: 0xAB, count: 32)
        #expect(window.submitPairRequest(firstToken, proof: wrongProof) == .rejected)
        #expect(window.attemptsRemaining == 2)

        let secondToken = try #require(window.admitCandidate())
        _ = window.candidateHellosCompleted(secondToken)
        decision.value = .trusted
        let correctProof = try PairingProof.compute(
            secret: secret, macSpkiDer: macSpkiDer, phoneSpkiDer: phoneSpkiDer, channelBinding: challenge
        )
        #expect(window.submitPairRequest(secondToken, proof: correctProof) == .rejected)

        decision.value = .pairingCandidate
        let thirdToken = try #require(window.admitCandidate())
        let secondChallenge = try #require(window.candidateHellosCompleted(thirdToken))
        let secondCorrectProof = try PairingProof.compute(
            secret: secret, macSpkiDer: macSpkiDer, phoneSpkiDer: phoneSpkiDer, channelBinding: secondChallenge
        )
        #expect(window.submitPairRequest(thirdToken, proof: secondCorrectProof) == .pendingConfirmation)
    }

    /// A real, structurally valid uncompressed P-256 SPKI DER (matching
    /// `PeerAuthorizerTests.makeValidSpkiDer()`'s construction): the fixed 26-byte
    /// `SubjectPublicKeyInfo` header followed by a freshly generated key's 65-byte
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
