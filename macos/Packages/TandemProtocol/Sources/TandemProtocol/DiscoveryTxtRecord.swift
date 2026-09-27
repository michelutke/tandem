import Foundation

/// Validates the wire shape of a `_tandem._tcp` Bonjour TXT record (E21-02, SPEC.md "Discovery TXT
/// record") before any of its fields are trusted: exactly the two keys `v` and `id`, `id` exactly
/// 16 hex characters, `v` exactly `"1"`. This is a shape check only -- `id`'s case is preserved
/// verbatim in ``Parsed``, never normalized, since `DiscoveryRotatingId.recognize(advertisedIdHex:
/// candidateHexIds:)` (TandemCrypto) treats case as significant.
public enum DiscoveryTxtRecord {
    public enum ValidationError: Error, Equatable {
        case malformedTxtRecord
        case unsupportedVersion
    }

    public struct Parsed: Equatable {
        public let version: String
        public let idHex: String
    }

    private static let supportedVersion = "1"
    private static let idHexLength = 16

    /// Throws ``ValidationError/malformedTxtRecord`` unless `fields` has exactly the keys `v` and
    /// `id`, and `id` is exactly ``idHexLength`` hex digits (any case -- this check is shape-only,
    /// not the separate case-sensitive recognition comparison). Only then throws
    /// ``ValidationError/unsupportedVersion`` unless `v` is `"1"`.
    public static func parse(fields: [String: String]) throws -> Parsed {
        guard
            Set(fields.keys) == Set(["v", "id"]),
            let idHex = fields["id"],
            idHex.count == idHexLength,
            idHex.allSatisfy(\.isHexDigit)
        else {
            throw ValidationError.malformedTxtRecord
        }

        guard let version = fields["v"], version == supportedVersion else {
            throw ValidationError.unsupportedVersion
        }

        return Parsed(version: version, idHex: idHex)
    }
}
