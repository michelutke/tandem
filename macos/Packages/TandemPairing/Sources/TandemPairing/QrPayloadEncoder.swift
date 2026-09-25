import Darwin
import Foundation
import TandemCrypto

/// The `tandem://pair` URI for one pairing window, plus the raw secret bytes that produced its
/// `s` field (the pairing window, E14-02, keeps this to verify the resulting proof). The secret
/// is single-use, sensitive material (`docs/protocol/SPEC.md` #2 "Secret handling"): never log,
/// persist or place it on a pasteboard -- ``description``/``debugDescription`` are redacted so an
/// accidental interpolation cannot leak either the secret or the URI (which itself encodes it).
public struct QrPayload: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let uri: String
    public let secret: Data

    public init(uri: String, secret: Data) {
        self.uri = uri
        self.secret = secret
    }

    public var description: String { "QrPayload(redacted)" }
    public var debugDescription: String { "QrPayload(redacted)" }
}

/// Builds the `tandem://pair` URI a Mac renders as a QR code for one open pairing window
/// (E14-01). Reference: `docs/protocol/SPEC.md` #2, `tools/vectors/qr_payload.py`.
public enum QrPayloadEncoder {
    /// SPEC.md #2: `a` lists 1 to 8 literal addresses.
    public static let maxAddressCount = 8
    /// SPEC.md #2: `n` decodes to at most 64 bytes.
    public static let maxNameBytes = 64

    /// Generates a fresh secret and reads the current local addresses, filters and caps them,
    /// and formats the `pair-uri`.
    public static func generate(
        fingerprint: SpkiFingerprint,
        secretSource: SecretSource,
        addressSource: LocalAddressSource,
        port: Int,
        name: String
    ) -> QrPayload {
        let secret = secretSource.generateSecret()
        let addresses = routableAddresses(from: addressSource.currentAddresses())
        let uri = encode(fingerprint: fingerprint, secret: secret, addresses: addresses, port: port, name: name)
        return QrPayload(uri: uri, secret: secret)
    }

    /// Pure formatter: joins already-decided field values into the `pair-uri` string with no
    /// filtering or validation of `addresses` -- callers that source addresses from live
    /// interfaces go through ``generate(fingerprint:secretSource:addressSource:port:name:)``
    /// above, which filters and caps before calling through to this function.
    public static func encode(
        fingerprint: SpkiFingerprint,
        secret: Data,
        addresses: [String],
        port: Int,
        name: String
    ) -> String {
        let fingerprintParam = base64URLNoPadding(fingerprint.bytes)
        let secretParam = base64URLNoPadding(secret)
        let addressParam = addresses.joined(separator: ",")
        let nameParam = percentEncodedName(truncatedUTF8(name, maxBytes: maxNameBytes))
        return "tandem://pair?v=1&fp=\(fingerprintParam)&s=\(secretParam)&a=\(addressParam)&p=\(port)&n=\(nameParam)"
    }

    /// Excludes loopback, IPv6 link-local and unspecified addresses (SPEC.md #2: "the Mac's own
    /// QR-rendering implementation simply never emits [a loopback address]"; a link-local address
    /// is never dialable off-host and would carry a zone ID the grammar forbids), then caps at
    /// ``maxAddressCount``.
    static func routableAddresses(from candidates: [String]) -> [String] {
        Array(candidates.filter(isRoutable).prefix(maxAddressCount))
    }

    static func isRoutable(_ literal: String) -> Bool {
        guard !literal.contains("%") else { return false }

        if let bytes = ipv4Bytes(literal) {
            return !(bytes.allSatisfy { $0 == 0 } || bytes[0] == 127)
        }
        if let bytes = ipv6Bytes(literal) {
            let isLoopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
            if bytes.allSatisfy({ $0 == 0 }) || isLoopback { return false }
            if bytes[0] == 0xFE, (bytes[1] & 0xC0) == 0x80 { return false }
            return true
        }
        return false
    }

    private static func ipv4Bytes(_ literal: String) -> [UInt8]? {
        var addr = in_addr()
        guard inet_pton(AF_INET, literal, &addr) == 1 else { return nil }
        return withUnsafeBytes(of: &addr) { Array($0) }
    }

    private static func ipv6Bytes(_ literal: String) -> [UInt8]? {
        var addr = in6_addr()
        guard inet_pton(AF_INET6, literal, &addr) == 1 else { return nil }
        return withUnsafeBytes(of: &addr) { Array($0) }
    }

    /// Truncates `name`'s UTF-8 encoding to at most `maxBytes`, backing off from a mid-scalar cut
    /// so the result is always valid, complete UTF-8 (SPEC.md #2's `n` field, E01-02).
    static func truncatedUTF8(_ name: String, maxBytes: Int) -> String {
        let utf8Bytes = Array(name.utf8)
        guard utf8Bytes.count > maxBytes else { return name }

        var end = maxBytes
        while end > 0, (utf8Bytes[end] & 0b1100_0000) == 0b1000_0000 {
            end -= 1
        }
        // `utf8Bytes[0..<end]` is a prefix ending exactly on a scalar boundary, so it is always
        // valid, complete UTF-8; the failable `String(bytes:encoding:)` initializer this rule
        // otherwise prefers would just re-verify that and can never actually return `nil` here.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: utf8Bytes[0..<end], as: UTF8.self)
    }

    private static let unreservedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func percentEncodedName(_ name: String) -> String {
        name.addingPercentEncoding(withAllowedCharacters: unreservedCharacters) ?? name
    }

    private static func base64URLNoPadding(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
