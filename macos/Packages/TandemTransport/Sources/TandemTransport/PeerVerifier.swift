import Foundation
import Security
import TandemCrypto

/// Builds the real `sec_protocol_verify_t` closure for the Mac's mTLS listener (E12-01),
/// implementing SPEC.md §1's verify-callback algorithm: extract the peer's leaf certificate (chain
/// index 0 only -- any additional certificates a peer sends are ignored and never used for trust
/// in any way, "Certificate handling and the leaf-only check"), read its actual candidate SPKI DER,
/// and hand the trust decision to ``PeerAuthorizer`` (E12-02) -- a pure function, so the actual
/// trust-store/pairing-window logic stays unit-testable without a real TLS handshake. This type is
/// exercised by `integration:` loopback tests instead.
public enum PeerVerifier {
    /// - Parameter onDecision: Called once per invocation of the returned block, after
    ///   ``PeerAuthorizer/decide(spki:trustStore:window:)`` has run and before `complete` is
    ///   called, with the connection's metadata, the decision reached, the candidate fingerprint
    ///   (`nil` only if the leaf's SPKI never parsed at all), and that same candidate's raw SPKI
    ///   DER (also `nil` only in that case). Surfaces `.trusted` / `.pairingCandidate` (and which
    ///   fingerprint/DER) to the connection that owns this handshake -- e.g. E14-07's "connection
    ///   classified `.pairingCandidate` by E12-02" -- without that caller re-deriving the decision
    ///   itself from live trust-store/window state after the fact (a TOCTOU risk: that state may
    ///   have already moved on by `.ready`). Defaults to a no-op.
    public static func makeVerifyBlock(
        trustStore: any TrustStoreReader,
        window: any PairingWindowState,
        onDecision: @escaping @Sendable (
            sec_protocol_metadata_t,
            PeerAuthorizationDecision,
            SpkiFingerprint?,
            Data?
        ) -> Void = { _, _, _, _ in }
    ) -> TandemVerifyBlock {
        { metadata, secTrust, complete in
            let trust = sec_trust_copy_ref(secTrust).takeRetainedValue()
            guard
                let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                let leaf = chain.first,
                let spkiDer = spkiDer(fromLeaf: leaf)
            else {
                onDecision(metadata, .rejected, nil, nil)
                complete(false)
                return
            }

            let decision = PeerAuthorizer.decide(spki: spkiDer, trustStore: trustStore, window: window)
            onDecision(metadata, decision, try? SpkiFingerprint.of(spkiDer: spkiDer), spkiDer)

            switch decision {
            case .trusted, .pairingCandidate:
                complete(true)
            case .rejected:
                complete(false)
            }
        }
    }

    /// Reads the leaf's actual candidate SPKI DER from its own certificate encoding
    /// (`SecCertificateCopyData`, ``TandemCrypto/LeafSpkiExtractor``) -- never reconstructed from a
    /// decoded key's canonical representation, so a compressed point or explicit EC parameters
    /// reach ``TandemCrypto/SpkiFingerprint/of(spkiDer:)`` as they actually are on the wire and are
    /// rejected there (SPEC.md §1: "a leaf key of any other type, curve, or point encoding... MUST
    /// fail... before the pin compare ever runs"), rather than being silently canonicalized away
    /// before validation ever sees them.
    static func spkiDer(fromLeaf certificate: SecCertificate) -> Data? {
        let certificateDer = SecCertificateCopyData(certificate) as Data
        return try? LeafSpkiExtractor.subjectPublicKeyInfoDER(certificateDER: certificateDer)
    }
}
