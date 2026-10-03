import CryptoKit
import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// `focus-encoding` category handler for ``ConformanceRunner`` (E72-04): decodes the raw message
/// bytes each vector describes (`input.messageHex` -- see `protocol/vectors/README.md`) with the
/// real generated focus-sync message types (`protocol/proto/tandem/v1/focus.proto`), selected by
/// `input.kind`.
extension ConformanceRunner {
    static func runFocusEncoding(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(FocusEncodingManifest.self, from: data)
        return try manifest.vectors.map(focusEncodingOutcome)
    }

    private static func focusEncodingOutcome(_ vector: FocusEncodingManifest.Vector) throws -> VectorOutcome {
        let bytes = try conformanceRunnerHexDecode(vector.input.messageHex)
        let decoded: (flag: Bool, reencoded: Data?)?
        switch vector.input.kind {
        case "focusState":
            decoded = (try? Tandem_V1_FocusState(serializedBytes: bytes)).map { ($0.on, try? $0.serializedData()) }
        case "focusSyncCapability":
            decoded = (try? Tandem_V1_FocusSyncCapability(serializedBytes: bytes))
                .map { ($0.available, try? $0.serializedData()) }
        default:
            throw ConformanceFailure(description: "unsupported focus-encoding kind: \(vector.input.kind)")
        }
        guard let decoded else {
            return VectorOutcome(
                id: vector.id, category: "focus-encoding", outcome: "fail",
                expected: "decodable", actual: "failed to decode"
            )
        }
        let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let passed = decoded.flag == vector.expected.flag && decoded.reencoded == bytes
            && sha == vector.expected.messageSha256
        return VectorOutcome(
            id: vector.id, category: "focus-encoding", outcome: passed ? "pass" : "fail",
            expected: "flag=\(vector.expected.flag)", actual: "flag=\(decoded.flag)"
        )
    }
}

struct FocusEncodingManifest: Decodable {
    struct Input: Decodable {
        let kind: String
        let messageHex: String
    }
    struct Expected: Decodable {
        let flag: Bool
        let messageSha256: String
    }
    struct Vector: Decodable {
        let id: String
        let input: Input
        let expected: Expected
    }
    let vectors: [Vector]
}
