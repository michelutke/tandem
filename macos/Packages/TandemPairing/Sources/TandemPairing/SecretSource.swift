import Foundation

/// Seam for the CSPRNG that mints the pairing secret (E14-01, `docs/protocol/SPEC.md` #2's `s`
/// field). Tests inject a fake; `SystemSecretSource` is the production implementation.
public protocol SecretSource: Sendable {
    /// Returns a freshly generated ``SystemSecretSource/secretByteCount``-byte secret. MUST be a
    /// new value on every call -- SPEC.md #2's "Pairing window": each window gets its own
    /// single-use secret, and regenerating always invalidates the previous one.
    func generateSecret() -> Data
}

/// Production `SecretSource`. `SystemRandomNumberGenerator` is documented as cryptographically
/// secure on Apple platforms (backed by `arc4random_buf`), satisfying SPEC.md #2's "16 bytes from
/// a CSPRNG".
public struct SystemSecretSource: SecretSource {
    public static let secretByteCount = 16

    public init() {}

    public func generateSecret() -> Data {
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: Self.secretByteCount)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        }
        return Data(bytes)
    }
}
