import CryptoKit
import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// `clipboard-encoding` category handler for ``ConformanceRunner`` (E31-01): decodes the raw
/// `ClipboardText` message bytes each vector describes (inlined as `clipboardTextHex`, or a
/// compact `textRecipe` -- see `protocol/vectors/README.md`) with the real generated
/// `Tandem_V1_ClipboardText` type, then validates `text`'s byte length against the CLIPBOARD
/// channel's 1,048,576-byte cap (docs/protocol/SPEC.md `#clipboard-channel`). Deliberately does
/// not go through `FrameEncoder`/`FrameDecoder`: wrapping a boundary vector in a full `Envelope`
/// frame would make the "exactly 1 MiB text is accepted" vector self-contradictory against the
/// frame's own, unrelated 1 MiB length cap (see `clipboard-encoding.json`'s entry in
/// `protocol/vectors/README.md`).
extension ConformanceRunner {
    static let maxClipboardTextBytes = 1_048_576

    static func runClipboardEncoding(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(ClipboardEncodingManifest.self, from: data)
        return try manifest.vectors.map { try clipboardEncodingOutcome($0) }
    }

    private static func clipboardEncodingOutcome(
        _ vector: ClipboardEncodingManifest.Vector
    ) throws -> VectorOutcome {
        let messageBytes = try clipboardTextBytes(for: vector.input)
        guard let decoded = try? Tandem_V1_ClipboardText(serializedBytes: messageBytes) else {
            return VectorOutcome(
                id: vector.id, category: "clipboard-encoding", outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }

        let textByteLength = decoded.text.utf8.count
        let accepted = textByteLength <= maxClipboardTextBytes

        if let expected = vector.expected {
            return try clipboardEncodingValidOutcome(
                vector: vector, decoded: decoded, accepted: accepted,
                textByteLength: textByteLength, expected: expected
            )
        }
        guard let expectedError = vector.expectedError else {
            throw ConformanceFailure(description: "vector \(vector.id) has neither expected nor expectedError")
        }
        let actual = accepted ? "accepted" : "clipboardTextTooLarge"
        return VectorOutcome(
            id: vector.id, category: "clipboard-encoding",
            outcome: actual == expectedError ? "pass" : "fail",
            expected: expectedError, actual: actual
        )
    }

    private static func clipboardEncodingValidOutcome(
        vector: ClipboardEncodingManifest.Vector,
        decoded: Tandem_V1_ClipboardText,
        accepted: Bool,
        textByteLength: Int,
        expected: ClipboardEncodingManifest.Expected
    ) throws -> VectorOutcome {
        guard accepted else {
            return VectorOutcome(
                id: vector.id, category: "clipboard-encoding", outcome: "fail",
                expected: "accepted", actual: "rejected: clipboardTextTooLarge"
            )
        }
        var passed = decoded.originTag == expected.originTag
            && decoded.contentHash.conformanceRunnerHex == expected.contentHashHex
            && decoded.sensitive == expected.sensitive
            && textByteLength == expected.textByteLength
        if let expectedText = expected.text {
            passed = passed && decoded.text == expectedText
        }
        if let expectedSha = expected.clipboardTextSha256 {
            let reencoded = try decoded.serializedData()
            passed = passed && sha256Hex(reencoded) == expectedSha
        } else if let hex = vector.input.clipboardTextHex {
            let reencoded = try decoded.serializedData()
            let expectedBytes = try conformanceRunnerHexDecode(hex)
            passed = passed && reencoded == expectedBytes
        }
        return VectorOutcome(
            id: vector.id, category: "clipboard-encoding",
            outcome: passed ? "pass" : "fail",
            expected: "originTag=\(expected.originTag) textByteLength=\(expected.textByteLength)",
            actual: "originTag=\(decoded.originTag) textByteLength=\(textByteLength)"
        )
    }

    private static func clipboardTextBytes(for input: ClipboardEncodingManifest.Input) throws -> Data {
        if let hex = input.clipboardTextHex {
            return try conformanceRunnerHexDecode(hex)
        }
        guard let recipe = input.textRecipe, let originTag = input.originTag,
              let sensitive = input.sensitive, let contentHashHex = input.contentHashHex else {
            throw ConformanceFailure(description: "clipboard-encoding vector missing textRecipe fields")
        }
        let fillByte = try conformanceRunnerHexDecode(recipe.fillByte)
        guard let byte = fillByte.first, let scalar = Unicode.Scalar(UInt32(byte)) else {
            throw ConformanceFailure(description: "textRecipe.fillByte must be one ASCII byte")
        }
        let text = String(repeating: Character(scalar), count: recipe.fillLength)
        var message = Tandem_V1_ClipboardText()
        message.originTag = originTag
        message.contentHash = try conformanceRunnerHexDecode(contentHashHex)
        message.text = text
        message.sensitive = sensitive
        return try message.serializedData()
    }

    private static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).conformanceRunnerHex
    }
}

struct ClipboardEncodingManifest: Decodable {
    struct TextRecipe: Decodable {
        let fillByte: String
        let fillLength: Int
    }
    struct Input: Decodable {
        let clipboardTextHex: String?
        let originTag: String?
        let sensitive: Bool?
        let contentHashHex: String?
        let textRecipe: TextRecipe?
    }
    struct Expected: Decodable {
        let originTag: String
        let contentHashHex: String
        let text: String?
        let sensitive: Bool
        let textByteLength: Int
        let clipboardTextSha256: String?
    }
    struct Vector: Decodable {
        let id: String
        let input: Input
        let expected: Expected?
        let expectedError: String?
    }
    let vectors: [Vector]
}
