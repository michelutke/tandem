import CryptoKit
import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// `media-control-encoding` category handler for ``ConformanceRunner`` (E72-02): decodes the raw
/// message bytes each vector describes (`input.messageHex` -- see `protocol/vectors/README.md`) with
/// the real generated media-control message types (`protocol/proto/tandem/v1/media_control.proto`),
/// selected by `input.kind`.
extension ConformanceRunner {
    static func runMediaControlEncoding(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(MediaControlEncodingManifest.self, from: data)
        return try manifest.vectors.map(mediaControlEncodingOutcome)
    }

    private static func mediaControlEncodingOutcome(
        _ vector: MediaControlEncodingManifest.Vector
    ) throws -> VectorOutcome {
        let bytes = try conformanceRunnerHexDecode(vector.input.messageHex)
        guard let decoded = try decodeMediaControlMessage(kind: vector.input.kind, bytes: bytes) else {
            return VectorOutcome(
                id: vector.id, category: "media-control-encoding", outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let passed = decoded.summary == vector.expected.summary && decoded.reencoded == bytes
            && sha == vector.expected.messageSha256
        return VectorOutcome(
            id: vector.id, category: "media-control-encoding", outcome: passed ? "pass" : "fail",
            expected: vector.expected.summary, actual: decoded.summary
        )
    }

    private static func decodeMediaControlMessage(
        kind: String,
        bytes: Data
    ) throws -> (summary: String, reencoded: Data?)? {
        switch kind {
        case "nowPlaying":
            return (try? Tandem_V1_NowPlaying(serializedBytes: bytes)).map { message in
                let album = message.hasAlbum ? message.album : "<absent>"
                let duration = message.hasDurationMs ? String(message.durationMs) : "<absent>"
                let summary = "title=\(message.title)|artist=\(message.artist)|state=\(message.state.rawValue)"
                    + "|album=\(album)|durationMs=\(duration)"
                return (summary, try? message.serializedData())
            }
        case "playPause":
            return (try? Tandem_V1_PlayPause(serializedBytes: bytes)).map { ("empty", try? $0.serializedData()) }
        case "next":
            return (try? Tandem_V1_Next(serializedBytes: bytes)).map { ("empty", try? $0.serializedData()) }
        case "previous":
            return (try? Tandem_V1_Previous(serializedBytes: bytes)).map { ("empty", try? $0.serializedData()) }
        case "stop":
            return (try? Tandem_V1_Stop(serializedBytes: bytes)).map { ("empty", try? $0.serializedData()) }
        case "capabilityUnavailable":
            return (try? Tandem_V1_CapabilityUnavailable(serializedBytes: bytes)).map {
                ("feature=\($0.feature.rawValue)", try? $0.serializedData())
            }
        default:
            throw ConformanceFailure(description: "unsupported media-control-encoding kind: \(kind)")
        }
    }
}

struct MediaControlEncodingManifest: Decodable {
    struct Input: Decodable {
        let kind: String
        let messageHex: String
    }
    struct Expected: Decodable {
        let summary: String
        let messageSha256: String
    }
    struct Vector: Decodable {
        let id: String
        let input: Input
        let expected: Expected
    }
    let vectors: [Vector]
}
