import Foundation

/// Seam for the CSPRNG that mints each media ticket (`docs/protocol/SPEC.md` § Media ticket,
/// invariant 6). Tests inject a deterministic fake; `SystemMediaTicketSource` is production.
public protocol MediaTicketSource: Sendable {
    /// Returns a freshly generated 32-byte ticket. MUST be a new value on every call.
    func generateTicket() -> Data
}

/// Production `MediaTicketSource`. `SystemRandomNumberGenerator` is documented as cryptographically
/// secure on Apple platforms (backed by `arc4random_buf`).
public struct SystemMediaTicketSource: MediaTicketSource {
    public init() {}

    public func generateTicket() -> Data {
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: MediaTicketTable<ContinuousClock>.ticketByteCount)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        }
        return Data(bytes)
    }
}
