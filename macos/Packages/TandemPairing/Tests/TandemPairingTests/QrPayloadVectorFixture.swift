import Foundation

/// Loads `protocol/vectors/qr-payload.json` (E01-21), the vector suite `QrPayloadEncoder`
/// (E14-01) reproduces the valid entries of.
enum QrPayloadVectorFixture {
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
        let expectedError: String?
    }

    struct Input: Decodable {
        let uri: String
    }

    struct Expected: Decodable {
        let version: String
        let fingerprintHex: String
        let secretHex: String
        let addresses: [String]
        let port: Int
        let nameHex: String
    }

    /// `#filePath` is this source file's on-disk path; walk up to the repo root
    /// (.../macos/Packages/TandemPairing/Tests/TandemPairingTests/<file> -> repo root), same
    /// walk-up count as `SpkiFingerprintVectorFixture.load()`.
    static func load() throws -> Manifest {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        url.appendPathComponent("protocol/vectors/qr-payload.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    static func hexDecode(_ hex: String) throws -> Data {
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
