import Foundation

/// Loads `protocol/vectors/display-strings.json` (E01-24), the vector suite validating
/// `DisplayStringSanitizer` (E01-23) on both platforms.
enum DisplayStringVectorFixture {
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
        let expected: Expected
    }

    struct Input: Decodable {
        let rawUtf8Hex: String
        let kind: String
    }

    struct Expected: Decodable {
        let sanitized: String
    }

    /// `#filePath` is this source file's on-disk path; walk up to the repo root
    /// (.../macos/Packages/TandemProtocol/Tests/TandemProtocolTests/<file> -> repo root), same
    /// walk-up count as `FrameEncodingVectorFixture.load()`.
    static func load() throws -> Manifest {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        url.appendPathComponent("protocol/vectors/display-strings.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    static func rawBytes(for entry: Entry) throws -> Data {
        try hexDecode(entry.input.rawUtf8Hex)
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
