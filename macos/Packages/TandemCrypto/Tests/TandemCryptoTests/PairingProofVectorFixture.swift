import Foundation

/// Loads `protocol/vectors/pairing-proof.json` (E01-18), the vector suite validating
/// `PairingProof` and `ConfirmationCode` (E10-13) on both platforms.
enum PairingProofVectorFixture {
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
        /// Present only on invalid entries: a stable, camelCase error name, e.g.
        /// `"malformedSpki"`, `"malformedProof"`, or `"proofMismatch"` (the last one is not a
        /// thrown error -- it's a `verify` result of `false`).
        let expectedError: String?
    }

    struct Input: Decodable {
        let kind: String
        let secretHex: String
        let macSpkiDerHex: String
        let phoneSpkiDerHex: String
        let cbHex: String
        /// Present only for `kind == "proof"`.
        let proofHex: String?
    }

    struct Expected: Decodable {
        /// Present only for `kind == "proof"` positive entries.
        let valid: Bool?
        /// Present only for `kind == "code"` entries.
        let code: String?
    }

    /// `#filePath` is this source file's on-disk path; walk up to the repo root
    /// (.../macos/Packages/TandemCrypto/Tests/TandemCryptoTests/<file> -> repo root), same
    /// walk-up count as `SpkiFingerprintVectorFixture.load()`.
    static func load() throws -> Manifest {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        url.appendPathComponent("protocol/vectors/pairing-proof.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    static func secret(for entry: Entry) throws -> Data {
        try hexDecode(entry.input.secretHex)
    }

    static func macSpkiDer(for entry: Entry) throws -> Data {
        try hexDecode(entry.input.macSpkiDerHex)
    }

    static func phoneSpkiDer(for entry: Entry) throws -> Data {
        try hexDecode(entry.input.phoneSpkiDerHex)
    }

    static func channelBinding(for entry: Entry) throws -> Data {
        try hexDecode(entry.input.cbHex)
    }

    static func proof(for entry: Entry) throws -> Data {
        guard let proofHex = entry.input.proofHex else {
            throw LoadError(description: "vector \(entry.id) has no proofHex")
        }
        return try hexDecode(proofHex)
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
