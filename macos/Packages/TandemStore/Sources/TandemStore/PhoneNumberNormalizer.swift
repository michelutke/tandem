import Foundation
import PhoneNumberKit

/// Derives the key two differently formatted spellings of one number share, so a lookup never
/// misses over formatting (E51-04). Parses with PhoneNumberKit relative to `defaultRegion`; a
/// number that does not parse falls back to the sender's E.164, then to its digits.
public final class PhoneNumberNormalizer: @unchecked Sendable {
    private let defaultRegion: String
    private let lock = NSLock()
    private let utility = PhoneNumberUtility()

    public init(defaultRegion: String = Locale.current.region?.identifier ?? "US") {
        self.defaultRegion = defaultRegion
    }

    public func lookupKey(for number: String, senderE164: String = "") -> String {
        if let parsed = normalizedE164(of: number) { return parsed }
        if !senderE164.isEmpty { return senderE164 }
        let digits = number.filter(\.isNumber)
        return digits.isEmpty ? number : digits
    }

    /// The E.164 form of a valid number, `nil` for anything libphonenumber would not call valid
    /// (invalid, short codes, alphanumeric sender ids); matches Android's `PhoneNormalizer`.
    public func normalizedE164(of number: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let parsed = try? utility.parse(number, withRegion: defaultRegion) else { return nil }
        return utility.format(parsed, toType: .e164)
    }
}
