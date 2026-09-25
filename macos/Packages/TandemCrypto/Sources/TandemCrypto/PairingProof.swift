import CryptoKit
import Foundation

/// HMAC-SHA256 pairing-proof helper (E10-13, SPEC.md #2 "Proof computation"): binds the pairing
/// secret to both peers' SPKIs and this session's channel-binding value so a `PairRequest.proof`
/// can only be produced (or verified) by someone who holds the secret and observed this exact
/// handshake. Consumed by E14-07 for verification; "no HMAC outside TandemCrypto" is enforced by
/// the E10-14 boundary check.
public enum PairingProof {
    public enum ValidationError: Error, Equatable {
        case malformedSpki
        case malformedChannelBinding
        case malformedProof
    }

    /// HMAC-SHA256 always produces a 32-byte digest.
    public static let expectedProofByteCount = 32

    private static let transcriptLabel = Data("tandem-pair-v1".utf8)

    /// `proof = HMAC-SHA256(secret, transcript)` where `transcript = ASCII("tandem-pair-v1") ||
    /// LP(macSpkiDer) || LP(phoneSpkiDer) || LP(channelBinding)` (SPEC.md #2). Throws before
    /// computing anything if `macSpkiDer`/`phoneSpkiDer` aren't 91-byte P-256 SPKI DER or
    /// `channelBinding` isn't 32 bytes.
    public static func compute(
        secret: Data,
        macSpkiDer: Data,
        phoneSpkiDer: Data,
        channelBinding: Data
    ) throws -> Data {
        guard PairingTranscript.validateSpkiPair(macSpkiDer: macSpkiDer, phoneSpkiDer: phoneSpkiDer) else {
            throw ValidationError.malformedSpki
        }
        guard PairingTranscript.validateChannelBinding(channelBinding) else {
            throw ValidationError.malformedChannelBinding
        }

        let transcript = PairingTranscript.build(
            label: transcriptLabel,
            macSpkiDer: macSpkiDer,
            phoneSpkiDer: phoneSpkiDer,
            channelBinding: channelBinding
        )
        let key = SymmetricKey(data: secret)
        return Data(HMAC<SHA256>.authenticationCode(for: transcript, using: key))
    }

    /// Recomputes `proof` from the verifier's own `secret`/`macSpkiDer`/`phoneSpkiDer`/
    /// `channelBinding` and compares it against the candidate `proof` in constant time
    /// (invariant 6, SPEC.md #2: "the Mac MUST recompute `proof` ... then compare ... in constant
    /// time"). Throws before any comparison if `proof` isn't exactly 32 bytes, or if the inputs
    /// fail `compute`'s own validation.
    public static func verify(
        proof: Data,
        secret: Data,
        macSpkiDer: Data,
        phoneSpkiDer: Data,
        channelBinding: Data
    ) throws -> Bool {
        guard proof.count == expectedProofByteCount else {
            throw ValidationError.malformedProof
        }
        let expected = try compute(
            secret: secret,
            macSpkiDer: macSpkiDer,
            phoneSpkiDer: phoneSpkiDer,
            channelBinding: channelBinding
        )
        return constantTimeEquals(expected, proof)
    }
}
