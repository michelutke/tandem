import Foundation

/// Seam for the CSPRNG that mints each pairing candidate's channel-binding challenge
/// (`docs/protocol/SPEC.md` § Pairing, D-67). Tests inject a fake; `SystemChallengeSource` is the
/// production implementation.
public protocol ChallengeSource: Sendable {
    /// Returns a freshly generated ``SystemChallengeSource/challengeByteCount``-byte challenge.
    /// MUST be a new value on every call -- the challenge is generated once per candidate
    /// connection and held for that candidate's lifetime only (``PairingWindow``).
    func generateChallenge() -> Data
}

/// Production `ChallengeSource`. `SystemRandomNumberGenerator` is documented as cryptographically
/// secure on Apple platforms (backed by `arc4random_buf`), satisfying SPEC.md's "fresh 32-byte
/// CSPRNG `challenge`".
public struct SystemChallengeSource: ChallengeSource {
    public static let challengeByteCount = 32

    public init() {}

    public func generateChallenge() -> Data {
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: Self.challengeByteCount)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        }
        return Data(bytes)
    }
}
