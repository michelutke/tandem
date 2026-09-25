import Foundation

/// Loads `protocol/vectors/frame-encoding.json` (E01-19) and reconstructs the exact wire bytes
/// each valid vector's `input` describes, mirroring `tools/vectors/frame_encoding.py`'s
/// `build_frame_from_vector`/`build_envelope_from_recipe` (see protocol/vectors/README.md's
/// "Compact recipes for large payloads" note for why `frame-max-size-exact` uses a recipe
/// instead of an inline `frameHex`).
enum FrameEncodingVectorFixture {
    struct LoadError: Error, CustomStringConvertible {
        let description: String
    }

    struct Manifest: Decodable {
        let vectors: [Entry]
    }

    struct Entry: Decodable {
        let id: String
        let input: Input
        let expected: Expected?
        /// Present only on invalid entries (E11-04): a stable, camelCase error name, e.g.
        /// `"malformedFrame"` (protocol/vectors/README.md).
        let expectedError: String?
        /// Present only on invalid entries: one of the frozen close-code names from
        /// docs/protocol/SPEC.md `#errors-and-close-codes`.
        let closeCode: String?
        /// Present only on invalid entries: the local diagnostic reason grouped under
        /// `closeCode`, e.g. `"TOO_LARGE"` (never sent on the wire).
        let localReason: String?
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

    struct Expected: Decodable {
        let channel: String
        let seq: UInt64
        let ack: UInt64
        let payload: String
        let envelopeLength: Int
        let frameSha256: String?
    }

    /// Channel name -> wire value, `protocol/proto/tandem/v1/envelope.proto`. Mirrors
    /// `tools/vectors/frame_encoding.py`'s `CHANNEL_VALUES`.
    static let channelValues: [String: Int] = [
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
    /// (.../macos/Packages/TandemProtocol/Tests/TandemProtocolTests/<file> -> repo root) rather
    /// than copying the vectors into the package (see E01-19 / protocol/vectors/README.md).
    static func load() throws -> Manifest {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        url.appendPathComponent("protocol/vectors/frame-encoding.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    /// The vectors E11-03 (encode-only) exercises: valid entries with an `expected` (not
    /// `expectedError`) result.
    static func validEntries(in manifest: Manifest) -> [Entry] {
        manifest.vectors.filter { $0.expected != nil }
    }

    /// The vectors E11-04 (decode rejection) exercises: invalid entries with an `expectedError`.
    static func invalidEntries(in manifest: Manifest) -> [Entry] {
        manifest.vectors.filter { $0.expectedError != nil }
    }

    /// Reconstructs the full frame (4-byte length prefix + serialized Envelope) an entry's
    /// `input` describes.
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
        return WireBuilder.frame(envelopeBytes: envelopeBytes, lengthPrefix: entry.input.lengthPrefix)
    }

    /// The Envelope bytes inside `frameBytes(for:)`, i.e. everything after the 4-byte prefix.
    static func envelopeBytes(for entry: Entry) throws -> Data {
        let frame = try frameBytes(for: entry)
        return frame.dropFirst(4)
    }

    private static func envelopeBytes(fromRecipe recipe: EnvelopeRecipe) throws -> Data {
        guard let channelValue = channelValues[recipe.channel] else {
            throw LoadError(description: "unknown channel \(recipe.channel)")
        }
        var parts = WireBuilder.fieldVarint(field: 1, value: Int(channelValue))
        if let seq = recipe.seq, seq != 0 {
            parts += WireBuilder.fieldVarint(field: 2, value: Int(seq))
        }
        if let ack = recipe.ack, ack != 0 {
            parts += WireBuilder.fieldVarint(field: 3, value: Int(ack))
        }
        if let payload = recipe.payload {
            guard payload.kind == "ring" else {
                throw LoadError(description: "unsupported recipe payload kind \(payload.kind)")
            }
            parts += WireBuilder.fieldLenDelimited(field: ringFieldNumber, payload: Data())
        }
        if let filler = recipe.filler {
            guard filler.wireType == "LENGTH_DELIMITED" else {
                throw LoadError(description: "unsupported filler wireType \(filler.wireType)")
            }
            guard let fillByte = UInt8(filler.fillByte, radix: 16) else {
                throw LoadError(description: "invalid filler fillByte \(filler.fillByte)")
            }
            let fillBytes = Data(repeating: fillByte, count: filler.fillLength)
            parts += WireBuilder.fieldLenDelimited(field: filler.fieldNumber, payload: fillBytes)
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
}

/// Minimal protobuf wire-format byte builder, mirroring `tools/vectors/frame_encoding.py`'s
/// encoder helpers. Used only to reconstruct vector fixtures and to build test envelopes of a
/// controlled size; production encoding goes through `FrameEncoder` + swift-protobuf.
enum WireBuilder {
    static func varint(_ value: Int) -> Data {
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

    static func tag(field: Int, wireType: Int) -> Data {
        varint((field << 3) | wireType)
    }

    static func fieldVarint(field: Int, value: Int) -> Data {
        tag(field: field, wireType: 0) + varint(value)
    }

    static func fieldLenDelimited(field: Int, payload: Data) -> Data {
        tag(field: field, wireType: 2) + varint(payload.count) + payload
    }

    static func frame(envelopeBytes: Data, lengthPrefix: Int) -> Data {
        let length = UInt32(lengthPrefix)
        var frame = Data(capacity: 4 + envelopeBytes.count)
        frame.append(UInt8(truncatingIfNeeded: length >> 24))
        frame.append(UInt8(truncatingIfNeeded: length >> 16))
        frame.append(UInt8(truncatingIfNeeded: length >> 8))
        frame.append(UInt8(truncatingIfNeeded: length))
        frame.append(envelopeBytes)
        return frame
    }

    /// Builds channel=STATUS(9), seq=1, an empty Ring payload (field 21), plus an unrecognized
    /// high-numbered filler field so the total serialized Envelope is exactly `totalBytes`.
    /// Mirrors `tools/vectors/frame_encoding.py`'s `solve_filler` + `build_envelope_from_recipe`.
    static func paddedRingEnvelope(totalBytes: Int) throws -> Data {
        let channelField = fieldVarint(field: 1, value: 9)
        let seqField = fieldVarint(field: 2, value: 1)
        let ringField = fieldLenDelimited(field: 21, payload: Data())
        let fixedOverhead = channelField.count + seqField.count + ringField.count
        let fillerFieldNumber = 500_000
        let tagLength = tag(field: fillerFieldNumber, wireType: 2).count

        var varintLengthGuess = 1
        for _ in 0..<16 {
            let fillLength = totalBytes - fixedOverhead - tagLength - varintLengthGuess
            guard fillLength >= 0 else {
                throw FrameEncodingVectorFixture.LoadError(
                    description: "totalBytes \(totalBytes) too small for the fixed overhead and filler tag"
                )
            }
            let actualLength = varint(fillLength).count
            if actualLength == varintLengthGuess {
                let filler = fieldLenDelimited(field: fillerFieldNumber, payload: Data(repeating: 0, count: fillLength))
                let result = channelField + seqField + ringField + filler
                guard result.count == totalBytes else {
                    throw FrameEncodingVectorFixture.LoadError(description: "filler did not resolve to totalBytes")
                }
                return result
            }
            varintLengthGuess = actualLength
        }
        throw FrameEncodingVectorFixture.LoadError(description: "failed to converge on a filler length")
    }
}
