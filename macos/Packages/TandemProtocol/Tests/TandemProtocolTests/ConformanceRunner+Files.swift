import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// `files-encoding` category handler for ``ConformanceRunner`` (E40-01): decodes the raw message
/// bytes each vector describes (`input.messageHex`, or `input.dataRecipe` for the oversized-chunk
/// vector -- see `protocol/vectors/README.md`) with the real generated FILES message types,
/// selected by `input.kind`. `fileChunk` vectors are additionally validated against the FILES
/// channel's 262,144-byte `data` cap (docs/protocol/SPEC.md `#files-channel` "Chunking") since
/// protobuf's `bytes` wire type has no inherent size limit of its own. Deliberately does not go
/// through `FrameEncoder`/`FrameDecoder`, for the same reason `clipboard-encoding.json` does not
/// (see `ConformanceRunner+Clipboard.swift`).
extension ConformanceRunner {
    static let maxFileChunkBytes = 262_144

    /// JSON `TRANSFER_REASON_*` name -> wire number, matching `tools/vectors/files_encoding.py`.
    static let transferReasonNumbers: [String: Int] = [
        "TRANSFER_REASON_UNSPECIFIED": 0,
        "TRANSFER_REASON_DECLINED": 1,
        "TRANSFER_REASON_TIMEOUT": 2,
        "TRANSFER_REASON_INSUFFICIENT_SPACE": 3,
        "TRANSFER_REASON_INVALID_NAME": 4,
        "TRANSFER_REASON_HASH_MISMATCH": 5,
        "TRANSFER_REASON_PROTOCOL_VIOLATION": 6,
        "TRANSFER_REASON_USER_CANCELLED": 7,
        "TRANSFER_REASON_UNKNOWN_TRANSFER": 8,
        "TRANSFER_REASON_SOURCE_UNAVAILABLE": 9,
        "TRANSFER_REASON_IO_ERROR": 10,
        "TRANSFER_REASON_BUSY": 11,
        "TRANSFER_REASON_TOO_LARGE": 12
    ]

    static func runFilesEncoding(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(FilesEncodingManifest.self, from: data)
        return try manifest.vectors.map { try filesEncodingOutcome($0) }
    }

    private static func filesEncodingOutcome(_ vector: FilesEncodingManifest.Vector) throws -> VectorOutcome {
        switch vector.input.kind {
        case "fileOffer": return try fileOfferOutcome(vector)
        case "fileAccept": return try fileAcceptOutcome(vector)
        case "fileReject": return try fileRejectOutcome(vector)
        case "fileChunk": return try fileChunkOutcome(vector)
        case "fileResumeRequest": return try fileResumeRequestOutcome(vector)
        default:
            throw ConformanceFailure(description: "unsupported files-encoding kind: \(vector.input.kind)")
        }
    }

    private static func messageBytes(_ vector: FilesEncodingManifest.Vector) throws -> Data {
        guard let hex = vector.input.messageHex else {
            throw ConformanceFailure(description: "files-encoding vector \(vector.id) missing messageHex")
        }
        return try conformanceRunnerHexDecode(hex)
    }

    private static func fileOfferOutcome(_ vector: FilesEncodingManifest.Vector) throws -> VectorOutcome {
        let bytes = try messageBytes(vector)
        guard let decoded = try? Tandem_V1_FileOffer(serializedBytes: bytes) else {
            return VectorOutcome(
                id: vector.id, category: "files-encoding", outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        guard let expected = vector.expected, let expectedSha256 = expected.sha256Hex,
              let expectedSize = expected.size, let expectedName = expected.name,
              let expectedId = expected.id, let expectedMime = expected.mime else {
            throw ConformanceFailure(description: "files-encoding vector \(vector.id) missing expected fields")
        }
        let actualSha256 = decoded.sha256.conformanceRunnerHex
        let passed = decoded.id == expectedId && decoded.name == expectedName
            && decoded.size == expectedSize && decoded.mime == expectedMime
            && actualSha256 == expectedSha256
        return VectorOutcome(
            id: vector.id, category: "files-encoding",
            outcome: passed ? "pass" : "fail", expected: expectedSha256, actual: actualSha256
        )
    }

    private static func fileAcceptOutcome(_ vector: FilesEncodingManifest.Vector) throws -> VectorOutcome {
        let bytes = try messageBytes(vector)
        guard let decoded = try? Tandem_V1_FileAccept(serializedBytes: bytes) else {
            return VectorOutcome(
                id: vector.id, category: "files-encoding", outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        guard let expectedId = vector.expected?.id else {
            throw ConformanceFailure(description: "files-encoding vector \(vector.id) missing expected.id")
        }
        return VectorOutcome(
            id: vector.id, category: "files-encoding",
            outcome: decoded.id == expectedId ? "pass" : "fail", expected: expectedId, actual: decoded.id
        )
    }

    private static func fileRejectOutcome(_ vector: FilesEncodingManifest.Vector) throws -> VectorOutcome {
        let bytes = try messageBytes(vector)
        guard let decoded = try? Tandem_V1_FileReject(serializedBytes: bytes) else {
            return VectorOutcome(
                id: vector.id, category: "files-encoding", outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        guard let expectedId = vector.expected?.id, let expectedReasonName = vector.expected?.reason,
              let expectedReasonNumber = transferReasonNumbers[expectedReasonName] else {
            throw ConformanceFailure(description: "files-encoding vector \(vector.id) missing expected reason")
        }
        let passed = decoded.id == expectedId && decoded.reason.rawValue == expectedReasonNumber
        return VectorOutcome(
            id: vector.id, category: "files-encoding",
            outcome: passed ? "pass" : "fail",
            expected: "id=\(expectedId) reason=\(expectedReasonName)",
            actual: "id=\(decoded.id) reason=\(decoded.reason.rawValue)"
        )
    }

    private static func fileResumeRequestOutcome(_ vector: FilesEncodingManifest.Vector) throws -> VectorOutcome {
        let bytes = try messageBytes(vector)
        guard let decoded = try? Tandem_V1_FileResumeRequest(serializedBytes: bytes) else {
            return VectorOutcome(
                id: vector.id, category: "files-encoding", outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        guard let expectedId = vector.expected?.id, let expectedFromOffset = vector.expected?.fromOffset else {
            throw ConformanceFailure(description: "files-encoding vector \(vector.id) missing expected fields")
        }
        let passed = decoded.id == expectedId && decoded.fromOffset == expectedFromOffset
        return VectorOutcome(
            id: vector.id, category: "files-encoding",
            outcome: passed ? "pass" : "fail",
            expected: "id=\(expectedId) fromOffset=\(expectedFromOffset)",
            actual: "id=\(decoded.id) fromOffset=\(decoded.fromOffset)"
        )
    }

    private static func fileChunkOutcome(_ vector: FilesEncodingManifest.Vector) throws -> VectorOutcome {
        let bytes = try fileChunkBytes(vector.input)
        guard let decoded = try? Tandem_V1_FileChunk(serializedBytes: bytes) else {
            return VectorOutcome(
                id: vector.id, category: "files-encoding", outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        let accepted = decoded.data.count <= maxFileChunkBytes

        if let expected = vector.expected {
            guard accepted else {
                return VectorOutcome(
                    id: vector.id, category: "files-encoding", outcome: "fail",
                    expected: "accepted", actual: "rejected: fileChunkPayloadTooLarge"
                )
            }
            guard let expectedId = expected.id, let expectedSeq = expected.seq,
                  let expectedOffset = expected.offset, let expectedDataHex = expected.dataHex else {
                throw ConformanceFailure(description: "files-encoding vector \(vector.id) missing expected fields")
            }
            let passed = decoded.id == expectedId && decoded.seq == expectedSeq
                && decoded.offset == expectedOffset && decoded.data.conformanceRunnerHex == expectedDataHex
            return VectorOutcome(
                id: vector.id, category: "files-encoding",
                outcome: passed ? "pass" : "fail",
                expected: "id=\(expectedId) seq=\(expectedSeq) offset=\(expectedOffset)",
                actual: "id=\(decoded.id) seq=\(decoded.seq) offset=\(decoded.offset)"
            )
        }
        guard let expectedError = vector.expectedError else {
            throw ConformanceFailure(description: "vector \(vector.id) has neither expected nor expectedError")
        }
        let actual = accepted ? "accepted" : "fileChunkPayloadTooLarge"
        return VectorOutcome(
            id: vector.id, category: "files-encoding",
            outcome: actual == expectedError ? "pass" : "fail",
            expected: expectedError, actual: actual
        )
    }

    private static func fileChunkBytes(_ input: FilesEncodingManifest.Input) throws -> Data {
        if let hex = input.messageHex {
            return try conformanceRunnerHexDecode(hex)
        }
        guard let recipe = input.dataRecipe, let id = input.id, let seq = input.seq,
              let offset = input.offset else {
            throw ConformanceFailure(description: "files-encoding fileChunk vector missing dataRecipe fields")
        }
        let fillByte = try conformanceRunnerHexDecode(recipe.fillByte)
        guard let byte = fillByte.first else {
            throw ConformanceFailure(description: "dataRecipe.fillByte must be one byte")
        }
        var message = Tandem_V1_FileChunk()
        message.id = id
        message.seq = UInt64(seq)
        message.offset = UInt64(offset)
        message.data = Data(repeating: byte, count: recipe.fillLength)
        return try message.serializedData()
    }
}

struct FilesEncodingManifest: Decodable {
    struct DataRecipe: Decodable {
        let fillByte: String
        let fillLength: Int
    }
    struct Input: Decodable {
        let kind: String
        let messageHex: String?
        let id: String?
        let seq: Int?
        let offset: Int?
        let dataRecipe: DataRecipe?
    }
    struct Expected: Decodable {
        let id: String?
        let name: String?
        let size: UInt64?
        let mime: String?
        let sha256Hex: String?
        let seq: UInt64?
        let offset: UInt64?
        let dataHex: String?
        let dataByteLength: Int?
        let fromOffset: UInt64?
        let reason: String?
    }
    struct Vector: Decodable {
        let id: String
        let input: Input
        let expected: Expected?
        let expectedError: String?
    }
    let vectors: [Vector]
}
