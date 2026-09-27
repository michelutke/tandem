import Foundation

/// Loads `protocol/vectors/heartbeat.json` (E20-01) and reconstructs the exact wire bytes
/// each vector's `input` describes. Heartbeat vectors follow the same frame-encoding structure
/// since a Heartbeat is an ordinary CONTROL-channel Envelope with an empty message payload.
enum HeartbeatVectorFixture {
    struct LoadError: Error, CustomStringConvertible {
        let description: String
    }

    struct Manifest: Decodable {
        let vectors: [Entry]

        init(vectors: [Entry]) {
            self.vectors = vectors
        }
    }

    struct Entry: Decodable {
        let id: String
        let description: String?
        let input: Input
        let expected: Expected?
        /// Present only on invalid entries: a stable, camelCase error name, e.g. `"malformedFrame"`.
        let expectedError: String?
        /// Present only on invalid entries: one of the frozen close-code names from
        /// docs/protocol/SPEC.md `#errors-and-close-codes`.
        let closeCode: String?
        /// Present only on invalid entries: the local diagnostic reason grouped under `closeCode`.
        let localReason: String?
    }

    struct Input: Decodable {
        let frameHex: String?
        let lengthPrefix: Int
        let suppliedEnvelopeLength: Int?
    }

    struct Expected: Decodable {
        let channel: String
        let seq: UInt64
        let ack: UInt64
        let payload: String
        let envelopeLength: Int
    }

    /// Loads `protocol/vectors/heartbeat.json` from the repo root.
    static func load(from data: Data) throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: data)
    }

    /// Reconstructs the full frame (4-byte length prefix + serialized Envelope) an entry's
    /// `input` describes.
    static func frameBytes(for entry: Entry) throws -> Data {
        guard let frameHex = entry.input.frameHex else {
            throw LoadError(description: "vector \(entry.id) has no frameHex")
        }
        return try hexDecode(frameHex)
    }

    /// The Envelope bytes inside `frameBytes(for:)`, i.e. everything after the 4-byte prefix.
    static func envelopeBytes(for entry: Entry) throws -> Data {
        let frame = try frameBytes(for: entry)
        return frame.dropFirst(4)
    }
}

private func hexDecode(_ hex: String) throws -> Data {
    guard hex.count.isMultiple(of: 2) else {
        throw HeartbeatVectorFixture.LoadError(description: "odd-length hex string: \(hex)")
    }
    var data = Data(capacity: hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index..<next], radix: 16) else {
            throw HeartbeatVectorFixture.LoadError(description: "invalid hex byte in \(hex)")
        }
        data.append(byte)
        index = next
    }
    return data
}
