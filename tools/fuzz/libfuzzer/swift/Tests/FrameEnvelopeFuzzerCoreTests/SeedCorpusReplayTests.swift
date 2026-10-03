import Foundation
import Testing
@testable import FrameEnvelopeFuzzerCore

/// E15-14: replays every vector in `protocol/vectors/frame-encoding.json` (E01-19) through
/// `fuzzOne` on a plain `swift test` — no sanitizer toolchain required. This is the
/// cross-platform half of the acceptance criterion "replaying the full seed corpus through the
/// real target produces 0 crashes": it proves the corpus contains nothing that traps the Swift
/// runtime; the ASan/libFuzzer half (memory-safety findings) only runs where `smoke.sh` can build
/// the real target (see README.md).
struct SeedCorpusReplayTests {
    @Test
    func fuzzOne_everySeedCorpusVector_doesNotCrash() throws {
        let manifest = try SeedCorpusVectors.load()
        #expect(!manifest.vectors.isEmpty)

        for vector in manifest.vectors {
            let frame = try SeedCorpusVectors.frameBytes(for: vector)
            fuzzOne(frame)
        }
    }

    /// E71-02: the Envelope target's seeds are each vector's frame minus its 4-byte length prefix.
    @Test
    func fuzzOneEnvelope_everySeedCorpusVector_doesNotCrash() throws {
        let manifest = try SeedCorpusVectors.load()
        #expect(!manifest.vectors.isEmpty)

        for vector in manifest.vectors {
            let frame = try SeedCorpusVectors.frameBytes(for: vector)
            fuzzOneEnvelope(frame.dropFirst(4))
        }
    }
}

/// Minimal reader for `protocol/vectors/frame-encoding.json`, independent of
/// `TandemProtocolTests`' own `FrameEncodingVectorFixture` (that type is internal to a different
/// test target). Only reconstructs frame *bytes* — this package never checks decoded output, only
/// that decoding a vector's bytes never crashes.
enum SeedCorpusVectors {
    struct LoadError: Error, CustomStringConvertible {
        let description: String
    }

    struct Manifest: Decodable {
        let vectors: [Entry]
    }

    struct Entry: Decodable {
        let id: String
        let input: Input
    }

    struct Input: Decodable {
        let frameHex: String?
        let envelopeRecipe: EnvelopeRecipe?
        let lengthPrefix: Int
        let envelopeLength: Int?
    }

    struct EnvelopeRecipe: Decodable {
        let channel: String
        let seq: UInt64?
        let ack: UInt64?
        let payload: PayloadRecipe?
        let filler: FillerRecipe?
    }

    struct PayloadRecipe: Decodable {
        let kind: String
    }

    struct FillerRecipe: Decodable {
        let fieldNumber: Int
        let wireType: String
        let fillByte: String
        let fillLength: Int
    }

    private static let channelValues: [String: Int] = [
        "CHANNEL_UNSPECIFIED": 0,
        "CHANNEL_CONTROL": 1,
        "CHANNEL_NOTIFY": 2,
        "CHANNEL_CLIPBOARD": 3,
        "CHANNEL_FILES": 4,
        "CHANNEL_SMS": 5,
        "CHANNEL_CONTACTS": 6,
        "CHANNEL_CALLS": 7,
        "CHANNEL_INPUT": 8,
        "CHANNEL_STATUS": 9
    ]

    private static let ringFieldNumber = 21

    /// `#filePath` is this source file's on-disk path; walk up to the repo root
    /// (.../tools/fuzz/libfuzzer/swift/Tests/FrameEnvelopeFuzzerCoreTests/<file> -> repo root)
    /// rather than copying the vectors into this package (see E01-19 / protocol/vectors/README.md).
    static func load() throws -> Manifest {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 {
            url.deleteLastPathComponent()
        }
        url.appendPathComponent("protocol/vectors/frame-encoding.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    static func frameBytes(for entry: Entry) throws -> Data {
        if let frameHex = entry.input.frameHex {
            return try hexDecode(frameHex)
        }
        guard let recipe = entry.input.envelopeRecipe, let envelopeLength = entry.input.envelopeLength else {
            throw LoadError(description: "vector \(entry.id) has neither frameHex nor envelopeRecipe")
        }
        let envelopeBytes = try self.envelopeBytes(fromRecipe: recipe)
        guard envelopeBytes.count == envelopeLength else {
            throw LoadError(description: "vector \(entry.id): envelopeRecipe did not reproduce envelopeLength")
        }
        return frame(envelopeBytes: envelopeBytes, lengthPrefix: entry.input.lengthPrefix)
    }

    private static func envelopeBytes(fromRecipe recipe: EnvelopeRecipe) throws -> Data {
        guard let channelValue = channelValues[recipe.channel] else {
            throw LoadError(description: "unknown channel \(recipe.channel)")
        }
        var parts = fieldVarint(field: 1, value: channelValue)
        if let seq = recipe.seq, seq != 0 {
            parts += fieldVarint(field: 2, value: Int(seq))
        }
        if let ack = recipe.ack, ack != 0 {
            parts += fieldVarint(field: 3, value: Int(ack))
        }
        if let payload = recipe.payload {
            guard payload.kind == "ring" else {
                throw LoadError(description: "unsupported recipe payload kind \(payload.kind)")
            }
            parts += fieldLenDelimited(field: ringFieldNumber, payload: Data())
        }
        if let filler = recipe.filler {
            guard filler.wireType == "LENGTH_DELIMITED" else {
                throw LoadError(description: "unsupported filler wireType \(filler.wireType)")
            }
            guard let fillByte = UInt8(filler.fillByte, radix: 16) else {
                throw LoadError(description: "invalid filler fillByte \(filler.fillByte)")
            }
            let fillBytes = Data(repeating: fillByte, count: filler.fillLength)
            parts += fieldLenDelimited(field: filler.fieldNumber, payload: fillBytes)
        }
        return parts
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

    private static func varint(_ value: Int) -> Data {
        precondition(value >= 0, "varint must be non-negative")
        var remaining = UInt64(value)
        var out = Data()
        while true {
            let byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 {
                out.append(byte | 0x80)
            } else {
                out.append(byte)
                break
            }
        }
        return out
    }

    private static func tag(field: Int, wireType: Int) -> Data {
        varint((field << 3) | wireType)
    }

    private static func fieldVarint(field: Int, value: Int) -> Data {
        tag(field: field, wireType: 0) + varint(value)
    }

    private static func fieldLenDelimited(field: Int, payload: Data) -> Data {
        tag(field: field, wireType: 2) + varint(payload.count) + payload
    }

    private static func frame(envelopeBytes: Data, lengthPrefix: Int) -> Data {
        let length = UInt32(lengthPrefix)
        var frame = Data(capacity: 4 + envelopeBytes.count)
        frame.append(UInt8(truncatingIfNeeded: length >> 24))
        frame.append(UInt8(truncatingIfNeeded: length >> 16))
        frame.append(UInt8(truncatingIfNeeded: length >> 8))
        frame.append(UInt8(truncatingIfNeeded: length))
        frame.append(envelopeBytes)
        return frame
    }
}
