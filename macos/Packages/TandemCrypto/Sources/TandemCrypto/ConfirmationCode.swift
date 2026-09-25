import CryptoKit
import Foundation

/// 6-digit pairing confirmation code (E10-13, SPEC.md #2 "Confirmation code"): both peers
/// independently derive this from the same `secret`, `macSpkiDer`, `phoneSpkiDer` and
/// `channelBinding` already used for `PairingProof`, and show it on their respective dialogs for
/// the user to compare.
public enum ConfirmationCode {
    public enum ValidationError: Error, Equatable {
        case malformedSpki
        case malformedChannelBinding
    }

    private static let transcriptLabel = Data("tandem-pair-code-v1".utf8)
    private static let modulus: UInt32 = 1_000_000

    /// `code = (u32be(first 4 bytes of HMAC-SHA256(secret, ASCII("tandem-pair-code-v1") ||
    /// LP(macSpkiDer) || LP(phoneSpkiDer) || LP(channelBinding)))) mod 1_000_000`, rendered
    /// zero-padded to exactly 6 digits (SPEC.md #2). Throws before computing anything if
    /// `macSpkiDer`/`phoneSpkiDer` aren't 91-byte P-256 SPKI DER or `channelBinding` isn't 32
    /// bytes.
    public static func compute(
        secret: Data,
        macSpkiDer: Data,
        phoneSpkiDer: Data,
        channelBinding: Data
    ) throws -> String {
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
        let digest = Data(HMAC<SHA256>.authenticationCode(for: transcript, using: key))
        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let code = value % modulus
        return String(format: "%06u", code)
    }
}
