import CryptoKit
import Foundation
import Testing
@testable import TandemCrypto

@Suite("RotationVerifier")
struct RotationVerifierTests {
    private let oldKey = P256.Signing.PrivateKey()
    private let newKey = P256.Signing.PrivateKey()
    private let challenge = Data(repeating: 0x42, count: RotationVerifier.challengeByteCount)

    private func signed(
        by key: P256.Signing.PrivateKey,
        new: Data? = nil,
        challenge: Data? = nil
    ) throws -> Data {
        let transcript = RotationVerifier.transcript(
            oldSpkiDer: oldKey.publicKey.derRepresentation,
            newSpkiDer: new ?? newKey.publicKey.derRepresentation,
            challenge: challenge ?? self.challenge
        )
        return try key.signature(for: transcript).derRepresentation
    }

    private func verify(sigOld: Data, sigNew: Data, newSpki: Data? = nil) -> Bool {
        RotationVerifier.verify(
            oldSpkiDer: oldKey.publicKey.derRepresentation,
            newSpkiDer: newSpki ?? newKey.publicKey.derRepresentation,
            challenge: challenge,
            sigOldKey: sigOld,
            sigNewKey: sigNew
        )
    }

    @Test
    func verify_bothSignaturesValid_returnsTrue() throws {
        #expect(verify(sigOld: try signed(by: oldKey), sigNew: try signed(by: newKey)))
    }

    @Test
    func transcript_layout_matchesSpec() {
        let transcript = RotationVerifier.transcript(
            oldSpkiDer: Data([1, 2]), newSpkiDer: Data([3]), challenge: Data([4, 5, 6])
        )

        let expected = Data("tandem-rotate-v1".utf8) + Data([0, 2, 1, 2, 0, 1, 3, 0, 3, 4, 5, 6])
        #expect(transcript == expected)
    }

    @Test
    func verify_sigOldMadeByNewKey_returnsFalse() throws {
        #expect(!verify(sigOld: try signed(by: newKey), sigNew: try signed(by: newKey)))
    }

    @Test
    func verify_sigNewMadeByOldKey_returnsFalse() throws {
        #expect(!verify(sigOld: try signed(by: oldKey), sigNew: try signed(by: oldKey)))
    }

    @Test
    func verify_signaturesOverOtherChallenge_returnsFalse() throws {
        let other = Data(repeating: 0x99, count: RotationVerifier.challengeByteCount)

        #expect(!verify(
            sigOld: try signed(by: oldKey, challenge: other),
            sigNew: try signed(by: newKey, challenge: other)
        ))
    }

    @Test
    func verify_truncatedSignature_returnsFalse() throws {
        let sigOld = try signed(by: oldKey)

        #expect(!verify(sigOld: sigOld.dropLast(), sigNew: try signed(by: newKey)))
    }

    @Test
    func verify_p384NewSpki_returnsFalse() throws {
        let p384 = P384.Signing.PrivateKey().publicKey.derRepresentation
        let sig = try signed(by: oldKey, new: p384)

        #expect(!verify(sigOld: sig, sigNew: sig, newSpki: p384))
    }

    @Test
    func verify_compressedPointNewSpki_returnsFalse() throws {
        var spki = Data(newKey.publicKey.derRepresentation.prefix(26))
        spki.append(newKey.publicKey.compressedRepresentation)
        let sig = try signed(by: oldKey, new: spki)

        #expect(!verify(sigOld: sig, sigNew: sig, newSpki: spki))
    }

    @Test
    func isStrictP256Spki_wrongLength_returnsFalse() {
        #expect(RotationVerifier.isStrictP256Spki(newKey.publicKey.derRepresentation))
        #expect(!RotationVerifier.isStrictP256Spki(newKey.publicKey.derRepresentation + Data([0])))
    }
}
