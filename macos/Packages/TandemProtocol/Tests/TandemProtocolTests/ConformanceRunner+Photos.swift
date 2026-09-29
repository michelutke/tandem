import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// `photos-encoding` category handler for ``ConformanceRunner`` (E41-01): decodes the raw message
/// bytes each vector describes (`input.messageHex` -- see `protocol/vectors/README.md`) with the
/// real generated Photos message types (`protocol/proto/tandem/v1/photos.proto`), selected by
/// `input.kind`. Deliberately does not go through `FrameEncoder`/`FrameDecoder`, for the same
/// reason `files-encoding.json` does not (see `ConformanceRunner+Files.swift`).
extension ConformanceRunner {
    static func runPhotosEncoding(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(PhotosEncodingManifest.self, from: data)
        return try manifest.vectors.map { try photosEncodingOutcome($0) }
    }

    private static func photosEncodingOutcome(_ vector: PhotosEncodingManifest.Vector) throws -> VectorOutcome {
        let bytes = try conformanceRunnerHexDecode(vector.input.messageHex)
        switch vector.input.kind {
        case "photoPageResult": return try photoPageResultOutcome(vector, bytes: bytes)
        case "thumbResult": return try thumbResultOutcome(vector, bytes: bytes)
        case "originalRequest": return try originalRequestOutcome(vector, bytes: bytes)
        case "photoError": return try photoErrorOutcome(vector, bytes: bytes)
        default:
            throw ConformanceFailure(description: "unsupported photos-encoding kind: \(vector.input.kind)")
        }
    }

    private static func photoPageResultOutcome(
        _ vector: PhotosEncodingManifest.Vector, bytes: Data
    ) throws -> VectorOutcome {
        guard let decoded = try? Tandem_V1_PhotoPageResult(serializedBytes: bytes) else {
            return VectorOutcome(
                id: vector.id, category: "photos-encoding", outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        guard let expected = vector.expected, let expectedItems = expected.items,
              let expectedNextCursor = expected.nextCursor, let expectedAccess = expected.access else {
            throw ConformanceFailure(description: "photos-encoding vector \(vector.id) missing expected fields")
        }
        let itemsMatch = decoded.items.count == expectedItems.count
            && zip(decoded.items, expectedItems).allSatisfy { actual, expectedItem in
                actual.id == expectedItem.id && actual.takenAt == expectedItem.takenAt
                    && actual.width == expectedItem.width && actual.height == expectedItem.height
            }
        let passed = itemsMatch && decoded.nextCursor == expectedNextCursor
            && decoded.access.rawValue == photoAccessNumbers[expectedAccess]
        return VectorOutcome(
            id: vector.id, category: "photos-encoding",
            outcome: passed ? "pass" : "fail",
            expected: "items=\(expectedItems.count) nextCursor=\(expectedNextCursor) access=\(expectedAccess)",
            actual: "items=\(decoded.items.count) nextCursor=\(decoded.nextCursor) access=\(decoded.access)"
        )
    }

    private static func thumbResultOutcome(
        _ vector: PhotosEncodingManifest.Vector, bytes: Data
    ) throws -> VectorOutcome {
        guard let decoded = try? Tandem_V1_ThumbResult(serializedBytes: bytes) else {
            return VectorOutcome(
                id: vector.id, category: "photos-encoding", outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        guard let expectedId = vector.expected?.id, let expectedPngBytesHex = vector.expected?.pngBytesHex else {
            throw ConformanceFailure(description: "photos-encoding vector \(vector.id) missing expected fields")
        }
        let actualPngBytesHex = decoded.pngBytes.conformanceRunnerHex
        let passed = decoded.id == expectedId && actualPngBytesHex == expectedPngBytesHex
        return VectorOutcome(
            id: vector.id, category: "photos-encoding",
            outcome: passed ? "pass" : "fail", expected: expectedPngBytesHex, actual: actualPngBytesHex
        )
    }

    private static func originalRequestOutcome(
        _ vector: PhotosEncodingManifest.Vector, bytes: Data
    ) throws -> VectorOutcome {
        guard let decoded = try? Tandem_V1_OriginalRequest(serializedBytes: bytes) else {
            return VectorOutcome(
                id: vector.id, category: "photos-encoding", outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        guard let expectedId = vector.expected?.id, let expectedTransferId = vector.expected?.transferId else {
            throw ConformanceFailure(description: "photos-encoding vector \(vector.id) missing expected fields")
        }
        let passed = decoded.id == expectedId && decoded.transferID == expectedTransferId
        return VectorOutcome(
            id: vector.id, category: "photos-encoding",
            outcome: passed ? "pass" : "fail",
            expected: "id=\(expectedId) transferId=\(expectedTransferId)",
            actual: "id=\(decoded.id) transferId=\(decoded.transferID)"
        )
    }

    private static func photoErrorOutcome(
        _ vector: PhotosEncodingManifest.Vector, bytes: Data
    ) throws -> VectorOutcome {
        guard let decoded = try? Tandem_V1_PhotoError(serializedBytes: bytes) else {
            return VectorOutcome(
                id: vector.id, category: "photos-encoding", outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        guard let expectedKind = vector.expected?.kind, let expectedKindNumber = photoErrorKindNumbers[expectedKind],
              let expectedRef = vector.expected?.ref,
              let expectedReason = vector.expected?.reason,
              let expectedReasonNumber = photoErrorReasonNumbers[expectedReason] else {
            throw ConformanceFailure(description: "photos-encoding vector \(vector.id) missing expected fields")
        }
        let passed = decoded.kind.rawValue == expectedKindNumber && decoded.ref == expectedRef
            && decoded.reason.rawValue == expectedReasonNumber
        return VectorOutcome(
            id: vector.id, category: "photos-encoding",
            outcome: passed ? "pass" : "fail",
            expected: "kind=\(expectedKind) ref=\(expectedRef) reason=\(expectedReason)",
            actual: "kind=\(decoded.kind.rawValue) ref=\(decoded.ref) reason=\(decoded.reason.rawValue)"
        )
    }

    /// JSON `PHOTO_ACCESS_*` name -> wire number, matching `tools/vectors/photos_encoding.py`.
    static let photoAccessNumbers: [String: Int] = [
        "PHOTO_ACCESS_UNSPECIFIED": 0,
        "PHOTO_ACCESS_FULL": 1,
        "PHOTO_ACCESS_PARTIAL": 2,
        "PHOTO_ACCESS_NONE": 3
    ]

    /// JSON `PHOTO_ERROR_KIND_*` name -> wire number, matching `tools/vectors/photos_encoding.py`.
    static let photoErrorKindNumbers: [String: Int] = [
        "PHOTO_ERROR_KIND_UNSPECIFIED": 0,
        "PHOTO_ERROR_KIND_PAGE": 1,
        "PHOTO_ERROR_KIND_THUMB": 2,
        "PHOTO_ERROR_KIND_ORIGINAL": 3
    ]

    /// JSON `PHOTO_ERROR_REASON_*` name -> wire number, matching `tools/vectors/photos_encoding.py`.
    static let photoErrorReasonNumbers: [String: Int] = [
        "PHOTO_ERROR_REASON_UNSPECIFIED": 0,
        "PHOTO_ERROR_REASON_NOT_FOUND": 1,
        "PHOTO_ERROR_REASON_ACCESS_DENIED": 2,
        "PHOTO_ERROR_REASON_INVALID_CURSOR": 3,
        "PHOTO_ERROR_REASON_BUSY": 4
    ]
}

struct PhotosEncodingManifest: Decodable {
    struct Input: Decodable {
        let kind: String
        let messageHex: String
    }
    struct PhotoMetaExpectation: Decodable {
        let id: String
        let takenAt: Int64
        let width: UInt32
        let height: UInt32
    }
    struct Expected: Decodable {
        let items: [PhotoMetaExpectation]?
        let nextCursor: String?
        let access: String?
        let id: String?
        let pngBytesHex: String?
        let pngBytesSha256: String?
        let transferId: String?
        let kind: String?
        let ref: String?
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
