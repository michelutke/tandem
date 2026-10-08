#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Commit-then-reveal short authentication string for manual pairing (E73-04, ADR-008,
/// SPEC.md "Manual pairing"). Both peers compute the same commitments and SAS from their own
/// observed SPKIs and channel-binding value; no fingerprint or fingerprint prefix is ever an
/// input here or a substitute for the SAS.
public enum ManualPairingSas {
    public enum ValidationError: Error, Equatable {
        case malformedSpki
        case malformedChannelBinding
        case malformedNonce
    }

    /// Which peer a commitment belongs to; the role byte stops a peer's own commitment being
    /// reflected back as the other side's.
    public enum Role: UInt8, Sendable {
        case phone = 0x01
        case mac = 0x02
    }

    /// The three values a manual-pairing transcript binds to: both SPKIs observed on this TLS
    /// handshake and this session's channel-binding value (`PairChallenge.challenge`).
    public struct Context: Sendable {
        public let macSpkiDer: Data
        public let phoneSpkiDer: Data
        public let channelBinding: Data

        public init(macSpkiDer: Data, phoneSpkiDer: Data, channelBinding: Data) {
            self.macSpkiDer = macSpkiDer
            self.phoneSpkiDer = phoneSpkiDer
            self.channelBinding = channelBinding
        }
    }

    public static let nonceByteCount = 16
    public static let commitmentByteCount = 32

    private static let pairLabel = Data("tandem-manual-pair-v1".utf8)
    private static let commitLabel = Data("tandem-manual-commit-v1".utf8)
    private static let modulus: UInt64 = 1_000_000

    /// `SHA-256(ASCII("tandem-manual-commit-v1") || roleByte || nonce || ctx)`.
    public static func commitment(
        role: Role,
        nonce: Data,
        context: Context
    ) throws -> Data {
        guard nonce.count == nonceByteCount else { throw ValidationError.malformedNonce }
        let transcript = try transcript(context)
        return Data(SHA256.hash(data: commitLabel + Data([role.rawValue]) + nonce + transcript))
    }

    /// Recomputes the commitment for `nonce` and compares it with `commitment` in constant time.
    /// `false` for any malformed input, so a caller can treat every failure the same way.
    public static func verifyCommitment(
        _ commitment: Data,
        role: Role,
        revealedNonce nonce: Data,
        context: Context
    ) -> Bool {
        guard let expected = try? Self.commitment(role: role, nonce: nonce, context: context) else {
            return false
        }
        return constantTimeEquals(expected, commitment)
    }

    /// `u64be(first 8 bytes of HMAC-SHA256(nonceP || nonceM, label || ctx)) mod 1_000_000`, rendered
    /// zero-padded to exactly 6 digits.
    public static func sas(
        noncePhone: Data,
        nonceMac: Data,
        context: Context
    ) throws -> String {
        guard noncePhone.count == nonceByteCount, nonceMac.count == nonceByteCount else {
            throw ValidationError.malformedNonce
        }
        let transcript = try transcript(context)
        let key = SymmetricKey(data: noncePhone + nonceMac)
        let digest = Data(HMAC<SHA256>.authenticationCode(for: pairLabel + transcript, using: key))
        let value = digest.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return String(format: "%06llu", value % modulus)
    }

    private static func transcript(_ context: Context) throws -> Data {
        guard PairingTranscript.validateSpkiPair(
            macSpkiDer: context.macSpkiDer, phoneSpkiDer: context.phoneSpkiDer
        ) else {
            throw ValidationError.malformedSpki
        }
        guard PairingTranscript.validateChannelBinding(context.channelBinding) else {
            throw ValidationError.malformedChannelBinding
        }
        return PairingTranscript.build(
            label: pairLabel,
            macSpkiDer: context.macSpkiDer,
            phoneSpkiDer: context.phoneSpkiDer,
            channelBinding: context.channelBinding
        )
    }
}
