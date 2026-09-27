import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// Shared category handler for ``ConformanceRunner`` categories whose vectors are complete
/// frame-encoding round-trips rather than a category-specific transform (E23-01 status-encoding,
/// E30-01 notify-encoding): every vector's frame bytes must round-trip byte-identically through
/// the real `FrameEncoder`/`FrameDecoder`.
extension ConformanceRunner {
    static func runFrameRoundTrip(category: String, data: Data) async throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(FrameRoundTripManifest.self, from: data)
        var outcomes: [VectorOutcome] = []
        for vector in manifest.vectors {
            let inputFrameBytes = try conformanceRunnerHexDecode(vector.input.frameHex)
            let decoded = try await decodeFrameForRoundTrip(inputFrameBytes)
            guard case .frame(let envelope) = decoded else {
                outcomes.append(VectorOutcome(
                    id: vector.id,
                    category: category,
                    outcome: "fail",
                    expected: vector.input.frameHex,
                    actual: "rejected: \(String(describing: decoded))"
                ))
                continue
            }

            let reencoded = try FrameEncoder.encode(envelope)
            let passed = inputFrameBytes == reencoded
            outcomes.append(VectorOutcome(
                id: vector.id,
                category: category,
                outcome: passed ? "pass" : "fail",
                expected: inputFrameBytes.conformanceRunnerHex,
                actual: reencoded.conformanceRunnerHex
            ))
        }
        return outcomes
    }

    private static func decodeFrameForRoundTrip(_ bytes: Data) async throws -> DecodeResult? {
        let pair = InMemoryConnectionPair(bufferCapacity: bytes.count + 8)
        try await pair.endA.send(bytes)
        await pair.endA.close()
        return try await FrameDecoder.decode(from: InMemoryFrameSource(pair.endB))
    }
}

struct FrameRoundTripManifest: Decodable {
    struct Vector: Decodable {
        let id: String
        let input: Input
    }
    struct Input: Decodable {
        let frameHex: String
    }
    let vectors: [Vector]
}
