import Foundation

/// Seam for the CSPRNG that mints the Mac's per-attempt manual-pairing nonce (ADR-008). Tests inject
/// a fake; ``SystemManualNonceSource`` is the production implementation.
public protocol ManualNonceSource: Sendable {
    /// Returns a freshly generated 16-byte nonce, new on every call (never reused across attempts).
    func generateNonce() -> Data
}

public struct SystemManualNonceSource: ManualNonceSource {
    public init() {}

    public func generateNonce() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<16).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) })
    }
}
