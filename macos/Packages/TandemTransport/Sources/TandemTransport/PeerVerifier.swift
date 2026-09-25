import Foundation
import Security
import TandemCrypto

/// Builds the real `sec_protocol_verify_t` closure for the Mac's mTLS listener (E12-01),
/// implementing SPEC.md §1's verify-callback algorithm: extract the peer's leaf certificate (chain
/// index 0 only -- any additional certificates a peer sends are ignored and never used for trust
/// in any way, "Certificate handling and the leaf-only check"), reconstruct its candidate SPKI DER,
/// and hand the trust decision to ``PeerAuthorizer`` (E12-02) -- a pure function, so the actual
/// trust-store/pairing-window logic stays unit-testable without a real TLS handshake. This type is
/// exercised by `integration:` loopback tests instead.
public enum PeerVerifier {
    public static func makeVerifyBlock(
        trustStore: any TrustStoreReader,
        window: any PairingWindowState
    ) -> TandemVerifyBlock {
        { _, secTrust, complete in
            let trust = sec_trust_copy_ref(secTrust).takeRetainedValue()
            guard
                let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                let leaf = chain.first,
                let spkiDer = spkiDer(fromLeaf: leaf)
            else {
                complete(false)
                return
            }

            switch PeerAuthorizer.decide(spki: spkiDer, trustStore: trustStore, window: window) {
            case .trusted, .pairingCandidate:
                complete(true)
            case .rejected:
                complete(false)
            }
        }
    }

    /// Reconstructs the leaf's candidate SPKI DER from its raw EC public key bytes (spike E03-01
    /// §2): only an uncompressed P-256 key -- exactly a 65-byte `0x04 ‖ X ‖ Y`
    /// `SecKeyCopyExternalRepresentation` of a 256-bit `kSecAttrKeyTypeECSECPrimeRandom` key --
    /// reconstructs to a value ``TandemCrypto/SpkiFingerprint`` will ever accept; any other key
    /// type or size returns `nil` here, before anything is ever hashed (SPEC.md §1: "a leaf key of
    /// any other type, curve, or point encoding... MUST fail... before the pin compare ever runs").
    static func spkiDer(fromLeaf certificate: SecCertificate) -> Data? {
        guard
            let key = SecCertificateCopyKey(certificate),
            let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
            (attributes[kSecAttrKeyType] as? String) == (kSecAttrKeyTypeECSECPrimeRandom as String),
            (attributes[kSecAttrKeySizeInBits] as? Int) == 256,
            let externalRepresentation = SecKeyCopyExternalRepresentation(key, nil) as Data?
        else {
            return nil
        }
        return uncompressedP256SpkiHeader + externalRepresentation
    }

    /// The fixed 26-byte DER prefix preceding a raw 65-byte uncompressed P-256 point in a
    /// `SubjectPublicKeyInfo` -- outer SEQUENCE, `AlgorithmIdentifier` SEQUENCE (OIDs
    /// `ecPublicKey`, `prime256v1`), and the BIT STRING header (tag, length, zero unused bits).
    /// 26 + 65 = 91 = ``TandemCrypto/SpkiFingerprint/expectedSpkiDerByteCount``.
    private static let uncompressedP256SpkiHeader: Data = Data([
        0x30, 0x59, 0x30, 0x13,
        0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
        0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07,
        0x03, 0x42, 0x00
    ])
}
