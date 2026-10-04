#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Receiver-side verification of a `KeyRotation` (SPEC.md #key-rotation, E70-05): the transcript
/// `ASCII("tandem-rotate-v1") || LP(oldSpkiDer) || LP(newSpkiDer) || LP(cb)` and the two ECDSA
/// P-256 / SHA-256 signatures over it, `sigOldKey` (authorizes) and `sigNewKey` (proof of
/// possession). `oldSpkiDer` is always the SPKI of the certificate that authenticated the session,
/// never a message field; `cb` is the receiver's own `RotationChallenge` for that session.
public enum RotationVerifier {
    /// A `RotationChallenge` (and so `cb`) is always exactly this many bytes.
    public static let challengeByteCount = 32

    private static let label = Data("tandem-rotate-v1".utf8)

    /// `true` only if `newSpkiDer` is a strict 91-byte uncompressed P-256 SPKI (SPEC.md #1) and both
    /// signatures verify over the transcript. Any malformed key, truncated or non-verifying
    /// signature yields `false`; the strict SPKI check runs before any signature work.
    public static func verify(
        oldSpkiDer: Data,
        newSpkiDer: Data,
        challenge: Data,
        sigOldKey: Data,
        sigNewKey: Data
    ) -> Bool {
        guard isStrictP256Spki(newSpkiDer) else { return false }
        let transcript = transcript(oldSpkiDer: oldSpkiDer, newSpkiDer: newSpkiDer, challenge: challenge)
        let oldKeyValid = isValid(signature: sigOldKey, over: transcript, spkiDer: oldSpkiDer)
        let newKeyValid = isValid(signature: sigNewKey, over: transcript, spkiDer: newSpkiDer)
        return oldKeyValid && newKeyValid
    }

    /// `true` if `spkiDer` is exactly the 91-byte DER SubjectPublicKeyInfo of an uncompressed
    /// ECDSA P-256 key (`SpkiFingerprint`'s own strict validation).
    public static func isStrictP256Spki(_ spkiDer: Data) -> Bool {
        (try? SpkiFingerprint.compute(spkiDer: spkiDer)) != nil
    }

    static func transcript(oldSpkiDer: Data, newSpkiDer: Data, challenge: Data) -> Data {
        label + lengthPrefixed(oldSpkiDer) + lengthPrefixed(newSpkiDer) + lengthPrefixed(challenge)
    }

    private static func lengthPrefixed(_ value: Data) -> Data {
        var prefixed = Data([UInt8((value.count >> 8) & 0xFF), UInt8(value.count & 0xFF)])
        prefixed.append(value)
        return prefixed
    }

    private static func isValid(signature: Data, over message: Data, spkiDer: Data) -> Bool {
        guard let publicKey = try? P256.Signing.PublicKey(derRepresentation: spkiDer),
              let ecdsaSignature = try? P256.Signing.ECDSASignature(derRepresentation: signature) else {
            return false
        }
        return publicKey.isValidSignature(ecdsaSignature, for: message)
    }
}
