import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// `status-encoding` category handler for ``ConformanceRunner`` (E23-01): DeviceStatus/Ring/
/// RingStop are tested like frame-encoding -- every vector's frame bytes must round-trip
/// byte-identically through the real `FrameEncoder`/`FrameDecoder`.
extension ConformanceRunner {
    static func runStatusEncoding(data: Data) async throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(StatusEncodingManifest.self, from: data)
        var outcomes: [VectorOutcome] = []
        for vector in manifest.vectors {
            let inputFrameBytes = try conformanceRunnerHexDecode(vector.input.frameHex)
            let decoded = try await decodeFrameForStatus(inputFrameBytes)
            guard case .frame(let envelope) = decoded else {
                outcomes.append(VectorOutcome(
                    id: vector.id,
                    category: "status-encoding",
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
                category: "status-encoding",
                outcome: passed ? "pass" : "fail",
                expected: inputFrameBytes.conformanceRunnerHex,
                actual: reencoded.conformanceRunnerHex
            ))
        }
        return outcomes
    }

    private static func decodeFrameForStatus(_ bytes: Data) async throws -> DecodeResult? {
        let pair = InMemoryConnectionPair(bufferCapacity: bytes.count + 8)
        try await pair.endA.send(bytes)
        await pair.endA.close()
        return try await FrameDecoder.decode(from: InMemoryFrameSource(pair.endB))
    }
}

struct StatusEncodingManifest: Decodable {
    struct Vector: Decodable {
        let id: String
        let input: Input
    }
    struct Input: Decodable {
        let frameHex: String
    }
    let vectors: [Vector]
}
