import CryptoKit
import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// `media-frame-encoding` category handler for ``ConformanceRunner`` (E61-01): decodes `MediaMessage`
/// bodies (`input.messageHex`), reassembles `MediaFrame` fragment sequences (`input.messagesHex`)
/// and runs prefix-only oversize frames (`input.frameHex`) through the framing layer; see
/// `protocol/vectors/README.md`.
extension ConformanceRunner {
    private static let mediaFrameCategory = "media-frame-encoding"
    private static let maxFragments = 8
    private static let fragmentViolation = "MALFORMED_FRAME:FRAGMENT_VIOLATION"

    static func runMediaFrameEncoding(data: Data) async throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(MediaFrameEncodingManifest.self, from: data)
        var outcomes: [VectorOutcome] = []
        for vector in manifest.vectors {
            outcomes.append(try await mediaFrameEncodingOutcome(vector))
        }
        return outcomes
    }

    private static func mediaFrameEncodingOutcome(
        _ vector: MediaFrameEncodingManifest.Vector
    ) async throws -> VectorOutcome {
        switch vector.input.kind {
        case "mediaFrameLengthPrefix": return try await mediaFramePrefixOutcome(vector)
        case "mediaFrameSequence": return try mediaFrameSequenceOutcome(vector)
        case "mediaFormat", "mediaFrame", "keyframeRequest", "rotationChanged":
            return try mediaMessageOutcome(vector)
        default:
            throw ConformanceFailure(description: "unsupported media-frame-encoding kind: \(vector.input.kind)")
        }
    }

    private static func mediaFramePrefixOutcome(
        _ vector: MediaFrameEncodingManifest.Vector
    ) async throws -> VectorOutcome {
        guard let hex = vector.input.frameHex, let closeCode = vector.closeCode,
              let localReason = vector.localReason else {
            throw ConformanceFailure(description: "media-frame-encoding vector \(vector.id) missing frame fields")
        }
        let result = try await decodeFrame(try conformanceRunnerHexDecode(hex))
        var actual = String(describing: result)
        if case .rejected(let code, let reason) = result, code == .malformedFrame {
            actual = "MALFORMED_FRAME:\(frameReasonName(reason))"
        }
        let expected = "\(closeCode):\(localReason)"
        return VectorOutcome(
            id: vector.id, category: mediaFrameCategory, outcome: actual == expected ? "pass" : "fail",
            expected: expected, actual: actual
        )
    }

    private static func mediaMessageOutcome(_ vector: MediaFrameEncodingManifest.Vector) throws -> VectorOutcome {
        guard let hex = vector.input.messageHex, let expected = vector.expected,
              let expectedSummary = expected.summary, let expectedSha = expected.messageSha256 else {
            throw ConformanceFailure(description: "media-frame-encoding vector \(vector.id) missing expected fields")
        }
        let bytes = try conformanceRunnerHexDecode(hex)
        guard let decoded = try? Tandem_V1_MediaMessage(serializedBytes: bytes) else {
            return VectorOutcome(
                id: vector.id, category: mediaFrameCategory, outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        let actualSummary = mediaMessageSummary(kind: vector.input.kind, message: decoded)
        let passed = actualSummary == expectedSummary && (try? decoded.serializedData()) == bytes
            && SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() == expectedSha
        return VectorOutcome(
            id: vector.id, category: mediaFrameCategory, outcome: passed ? "pass" : "fail",
            expected: expectedSummary, actual: actualSummary
        )
    }

    private static func mediaMessageSummary(kind: String, message: Tandem_V1_MediaMessage) -> String {
        switch (kind, message.payload) {
        case ("mediaFormat", .mediaFormat(let format)?):
            return "codec=\(format.codec.rawValue)|width=\(format.width)|height=\(format.height)|fps=\(format.fps)"
        case ("mediaFrame", .mediaFrame(let frame)?):
            return "pts=\(frame.pts)|flags=\(frame.flags)|dataLength=\(frame.data.count)"
                + "|index=\(frame.fragmentIndex)|count=\(frame.fragmentCount)"
        case ("keyframeRequest", .keyframeRequest?):
            return "empty"
        case ("rotationChanged", .rotationChanged(let rotation)?):
            return "orientation=\(rotation.orientation.rawValue)"
        default:
            return "payload=\(String(describing: message.payload))"
        }
    }

    private static func mediaFrameSequenceOutcome(
        _ vector: MediaFrameEncodingManifest.Vector
    ) throws -> VectorOutcome {
        guard let messagesHex = vector.input.messagesHex else {
            throw ConformanceFailure(description: "media-frame-encoding vector \(vector.id) missing messagesHex")
        }
        var fragments: [Tandem_V1_MediaFrame] = []
        for hex in messagesHex {
            let message = try Tandem_V1_MediaMessage(serializedBytes: try conformanceRunnerHexDecode(hex))
            fragments.append(message.mediaFrame)
        }
        let result = reassembleMediaFragments(fragments)
        if let expected = vector.expected {
            guard let expectedSha = expected.reassembledSha256, let expectedLength = expected.reassembledLength else {
                throw ConformanceFailure(description: "media-frame-encoding vector \(vector.id) missing expected")
            }
            let expectedText = "length=\(expectedLength) sha256=\(expectedSha)"
            guard let unit = result.accessUnit else {
                return VectorOutcome(
                    id: vector.id, category: mediaFrameCategory, outcome: "fail",
                    expected: expectedText, actual: "rejected@\(String(describing: result.rejectedAt))"
                )
            }
            let sha = SHA256.hash(data: unit).map { String(format: "%02x", $0) }.joined()
            return VectorOutcome(
                id: vector.id, category: mediaFrameCategory,
                outcome: sha == expectedSha && unit.count == expectedLength ? "pass" : "fail",
                expected: expectedText, actual: "length=\(unit.count) sha256=\(sha)"
            )
        }
        guard let expectedIndex = vector.input.rejectedAtIndex else {
            throw ConformanceFailure(description: "vector \(vector.id) has neither expected nor rejectedAtIndex")
        }
        let expectedText = "\(fragmentViolation)@\(expectedIndex)"
        let actual = result.rejectedAt.map { "\(fragmentViolation)@\($0)" } ?? "accepted"
        return VectorOutcome(
            id: vector.id, category: mediaFrameCategory, outcome: actual == expectedText ? "pass" : "fail",
            expected: expectedText, actual: actual
        )
    }

    /// SPEC.md #media-frame-semantics fragmentation rule over one access unit's fragments.
    private static func reassembleMediaFragments(
        _ fragments: [Tandem_V1_MediaFrame]
    ) -> (accessUnit: Data?, rejectedAt: Int?) {
        var buffer = Data()
        var first: Tandem_V1_MediaFrame?
        for (position, fragment) in fragments.enumerated() {
            let violates: Bool
            if let head = first {
                violates = fragment.pts != head.pts || fragment.fragmentCount != head.fragmentCount
                    || Int(fragment.fragmentIndex) != position
            } else {
                violates = !(1...maxFragments).contains(Int(fragment.fragmentCount)) || fragment.fragmentIndex != 0
            }
            if violates { return (nil, position) }
            if first == nil { first = fragment }
            buffer.append(fragment.data)
            if fragment.fragmentIndex == fragment.fragmentCount - 1 { return (buffer, nil) }
        }
        return (nil, nil)
    }
}

struct MediaFrameEncodingManifest: Decodable {
    struct Input: Decodable {
        let kind: String
        let messageHex: String?
        let messagesHex: [String]?
        let frameHex: String?
        let rejectedAtIndex: Int?
    }
    struct Expected: Decodable {
        let summary: String?
        let messageSha256: String?
        let reassembledLength: Int?
        let reassembledSha256: String?
    }
    struct Vector: Decodable {
        let id: String
        let input: Input
        let expected: Expected?
        let closeCode: String?
        let localReason: String?
    }
    let vectors: [Vector]
}
