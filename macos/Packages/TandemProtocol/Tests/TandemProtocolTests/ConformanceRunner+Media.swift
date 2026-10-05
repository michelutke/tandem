import CryptoKit
import Foundation
import SwiftProtobuf
import TandemTestSupport
@testable import TandemProtocol

/// `media-encoding` category handler for ``ConformanceRunner`` (E60-01): decodes the raw message
/// bytes each vector describes (`input.messageHex` -- see `protocol/vectors/README.md`) with the
/// real generated media-ticket message types (`protocol/proto/tandem/v1/media.proto`,
/// `control.proto`), selected by `input.kind`.
extension ConformanceRunner {
    private static let mediaTicketLength = 32
    private static let mirrorSessionIdLength = 16

    static func runMediaEncoding(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(MediaEncodingManifest.self, from: data)
        return try manifest.vectors.map(mediaEncodingOutcome)
    }

    private static func mediaEncodingOutcome(_ vector: MediaEncodingManifest.Vector) throws -> VectorOutcome {
        let bytes = try conformanceRunnerHexDecode(vector.input.messageHex)
        switch vector.input.kind {
        case "requestMediaTicket":
            return try emptyMessageOutcome(
                vector, bytes: bytes, reencode: Self.reencoded(Tandem_V1_RequestMediaTicket.self)
            )
        case "mirrorRequest":
            return try emptyMessageOutcome(
                vector, bytes: bytes, reencode: Self.reencoded(Tandem_V1_MirrorRequest.self)
            )
        case "mirrorDeclined":
            return try emptyMessageOutcome(
                vector, bytes: bytes, reencode: Self.reencoded(Tandem_V1_MirrorDeclined.self)
            )
        case "mediaTicketGrant": return try mediaTicketGrantOutcome(vector, bytes: bytes)
        case "mediaHello": return try mediaHelloOutcome(vector, bytes: bytes)
        default:
            throw ConformanceFailure(description: "unsupported media-encoding kind: \(vector.input.kind)")
        }
    }

    private static func mediaUndecodable(_ vector: MediaEncodingManifest.Vector) -> VectorOutcome {
        VectorOutcome(
            id: vector.id, category: "media-encoding", outcome: "fail",
            expected: "decodable", actual: "failed to decode"
        )
    }

    private static func sha256Hex(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func reencoded<Message: SwiftProtobuf.Message>(_ type: Message.Type) -> (Data) -> Data?? {
        { bytes in (try? Message(serializedBytes: bytes)).map { try? $0.serializedData() } }
    }

    private static func emptyMessageOutcome(
        _ vector: MediaEncodingManifest.Vector, bytes: Data, reencode: (Data) -> Data??
    ) throws -> VectorOutcome {
        guard let reencoded = reencode(bytes) else {
            return mediaUndecodable(vector)
        }
        guard let expectedSha = vector.expected?.messageSha256 else {
            throw ConformanceFailure(description: "media-encoding vector \(vector.id) missing expected fields")
        }
        let passed = reencoded == bytes && sha256Hex(bytes) == expectedSha
        return VectorOutcome(
            id: vector.id, category: "media-encoding", outcome: passed ? "pass" : "fail",
            expected: "sha256=\(expectedSha)", actual: "sha256=\(sha256Hex(bytes))"
        )
    }

    private static func mediaTicketGrantOutcome(
        _ vector: MediaEncodingManifest.Vector, bytes: Data
    ) throws -> VectorOutcome {
        guard let decoded = try? Tandem_V1_MediaTicketGrant(serializedBytes: bytes) else {
            return mediaUndecodable(vector)
        }
        guard let expected = vector.expected, let expectedTicketHex = expected.ticketHex,
              let expectedExpiresAt = expected.expiresAt, let expectedSha = expected.messageSha256 else {
            throw ConformanceFailure(description: "media-encoding vector \(vector.id) missing expected fields")
        }
        let expectedTicket = try conformanceRunnerHexDecode(expectedTicketHex)
        let passed = decoded.ticket == expectedTicket && decoded.expiresAt == expectedExpiresAt
            && (try? decoded.serializedData()) == bytes && sha256Hex(bytes) == expectedSha
        return VectorOutcome(
            id: vector.id, category: "media-encoding", outcome: passed ? "pass" : "fail",
            expected: "ticketLength=\(expectedTicket.count) expiresAt=\(expectedExpiresAt)",
            actual: "ticketLength=\(decoded.ticket.count) expiresAt=\(decoded.expiresAt)"
        )
    }

    private static func mediaHelloOutcome(
        _ vector: MediaEncodingManifest.Vector, bytes: Data
    ) throws -> VectorOutcome {
        guard let decoded = try? Tandem_V1_MediaHello(serializedBytes: bytes) else {
            return mediaUndecodable(vector)
        }
        let actual = decoded.ticket.count != mediaTicketLength ? "ticketRejected"
            : decoded.mirrorSessionID.count != mirrorSessionIdLength ? "malformedFrame" : "accepted"
        if let expected = vector.expected {
            guard let expectedTicketHex = expected.ticketHex, let expectedSha = expected.messageSha256,
                  let expectedMirrorIdHex = expected.mirrorSessionIdHex else {
                throw ConformanceFailure(description: "media-encoding vector \(vector.id) missing expected fields")
            }
            let expectedTicket = try conformanceRunnerHexDecode(expectedTicketHex)
            let expectedMirrorId = try conformanceRunnerHexDecode(expectedMirrorIdHex)
            let passed = actual == "accepted" && decoded.ticket == expectedTicket
                && decoded.mirrorSessionID == expectedMirrorId
                && (try? decoded.serializedData()) == bytes && sha256Hex(bytes) == expectedSha
            return VectorOutcome(
                id: vector.id, category: "media-encoding", outcome: passed ? "pass" : "fail",
                expected: "accepted", actual: actual
            )
        }
        guard let expectedError = vector.expectedError else {
            throw ConformanceFailure(description: "vector \(vector.id) has neither expected nor expectedError")
        }
        return VectorOutcome(
            id: vector.id, category: "media-encoding", outcome: actual == expectedError ? "pass" : "fail",
            expected: expectedError, actual: actual
        )
    }
}

struct MediaEncodingManifest: Decodable {
    struct Input: Decodable {
        let kind: String
        let messageHex: String
    }
    struct Expected: Decodable {
        let ticketHex: String?
        let mirrorSessionIdHex: String?
        let expiresAt: Int64?
        let messageSha256: String?
    }
    struct Vector: Decodable {
        let id: String
        let input: Input
        let expected: Expected?
        let expectedError: String?
    }
    let vectors: [Vector]
}
