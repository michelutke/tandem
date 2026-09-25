import Foundation

/// Loads `protocol/vectors/spki-fingerprint.json` (E01-17), the vector suite validating
/// `SpkiFingerprint` (E10-08) on both platforms.
enum SpkiFingerprintVectorFixture {
    struct LoadError: Error, CustomStringConvertible {
        let description: String
    }

    struct Manifest: Decodable {
        let vectors: [Entry]
    }

    struct Entry: Decodable {
        let id: String
        let description: String
        let input: Input
        let expected: Expected?
        /// Present only on invalid entries: a stable, camelCase error name matching a
        /// `SpkiFingerprint.ValidationError` case, e.g. `"unsupportedKeyType"`.
        let expectedError: String?
    }

    struct Input: Decodable {
        let spkiDerHex: String
    }

    struct Expected: Decodable {
        let fingerprintHex: String
    }

    /// `#filePath` is this source file's on-disk path; walk up to the repo root
    /// (.../macos/Packages/TandemCrypto/Tests/TandemCryptoTests/<file> -> repo root), same
    /// walk-up count as `FrameEncodingVectorFixture.load()`.
    static func load() throws -> Manifest {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        url.appendPathComponent("protocol/vectors/spki-fingerprint.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    static func spkiDer(for entry: Entry) throws -> Data {
        try hexDecode(entry.input.spkiDerHex)
    }

    private static func hexDecode(_ hex: String) throws -> Data {
        guard hex.count.isMultiple(of: 2) else {
            throw LoadError(description: "odd-length hex string")
        }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                throw LoadError(description: "invalid hex byte in \(hex)")
            }
            data.append(byte)
            index = next
        }
        return data
    }
}
