import Foundation

/// Shared length-prefixed transcript construction and input validation for the pairing proof
/// (`PairingProof`) and confirmation code (`ConfirmationCode`) (SPEC.md #2 "Proof computation" /
/// "Confirmation code"): both are HMAC-SHA256 over the same `LP(macSpkiDer) || LP(phoneSpkiDer) ||
/// LP(channelBinding)` fields, differing only in their leading ASCII label.
enum PairingTranscript {
    /// `macSpkiDer` and `phoneSpkiDer` are both 91-byte uncompressed P-256 SubjectPublicKeyInfo
    /// DER (SPEC.md #1, #2).
    static let spkiDerByteCount = SpkiFingerprint.expectedSpkiDerByteCount

    /// `channelBinding` (SPEC.md's `cb`) is exactly the 32 bytes of the `PairChallenge` this
    /// session's Mac sent (SPEC.md #1, #2).
    static let channelBindingByteCount = 32

    static func validateSpkiPair(macSpkiDer: Data, phoneSpkiDer: Data) -> Bool {
        macSpkiDer.count == spkiDerByteCount && phoneSpkiDer.count == spkiDerByteCount
    }

    static func validateChannelBinding(_ channelBinding: Data) -> Bool {
        channelBinding.count == channelBindingByteCount
    }

    /// `label || LP(macSpkiDer) || LP(phoneSpkiDer) || LP(channelBinding)`, where
    /// `LP(x) = u16be(len(x)) || x` (SPEC.md #2 Proof computation).
    static func build(label: Data, macSpkiDer: Data, phoneSpkiDer: Data, channelBinding: Data) -> Data {
        label + lengthPrefixed(macSpkiDer) + lengthPrefixed(phoneSpkiDer) + lengthPrefixed(channelBinding)
    }

    private static func lengthPrefixed(_ value: Data) -> Data {
        let count = value.count
        var prefixed = Data([UInt8((count >> 8) & 0xFF), UInt8(count & 0xFF)])
        prefixed.append(value)
        return prefixed
    }
}
