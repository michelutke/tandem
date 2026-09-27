import Foundation

/// Loads `protocol/vectors/discovery-id.json` (E01-20), the vector suite validating
/// `DiscoveryRotatingId` (E21-02) on both platforms. Only the `computeId`-kind vectors are
/// decoded here -- `recognition`/`txtRecord` are already fully covered by the generic
/// `ConformanceRunnerTests` suite in `TandemProtocolTests`.
enum DiscoveryRotatingIdVectorFixture {
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
    }

    struct Input: Decodable {
        let kind: String
        let macSpkiFingerprintHex: String?
        let unixSecondsUtc: Int64?
    }

    /// `computeId`'s own shape; other kinds' `expected` objects (`recognition`'s
    /// `receiverDayIndex`/`candidateIdsHex`/`advertisedIdHex`/`recognized`) decode fine against
    /// this struct too since both fields here are optional and unknown keys are ignored -- this
    /// fixture only ever reads them for `kind == "computeId"` entries.
    struct Expected: Decodable {
        let dayIndex: Int64?
        let idHex: String?
    }

    /// `#filePath` is this source file's on-disk path; walk up to the repo root
    /// (.../macos/Packages/TandemCrypto/Tests/TandemCryptoTests/<file> -> repo root), same
    /// walk-up count as `SpkiFingerprintVectorFixture.load()`.
    static func load() throws -> Manifest {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        url.appendPathComponent("protocol/vectors/discovery-id.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    static func macSpkiFingerprint(for entry: Entry) throws -> Data {
        guard let hex = entry.input.macSpkiFingerprintHex else {
            throw LoadError(description: "vector \(entry.id) has no macSpkiFingerprintHex")
        }
        return try hexDecode(hex)
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
