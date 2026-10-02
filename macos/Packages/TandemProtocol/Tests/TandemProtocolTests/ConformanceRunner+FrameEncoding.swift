import CryptoKit
import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// `frame-encoding` category handler for ``ConformanceRunner`` (E15-02): round-trips every valid
/// vector through the real `FrameEncoder`/`FrameDecoder` and asserts every invalid vector is
/// rejected with its tagged close code, mirroring `FrameCodecConformanceTests` (E11-12) but
/// producing a ``ConformanceRunner/VectorOutcome`` instead of a `#expect`.
extension ConformanceRunner {
    static func runFrameEncoding(data: Data) async throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(FrameEncodingVectorFixture.Manifest.self, from: data)
        var outcomes: [VectorOutcome] = []
        for entry in manifest.vectors {
            if entry.expected != nil {
                outcomes.append(try await frameEncodingValidOutcome(entry))
            } else {
                outcomes.append(try await frameEncodingInvalidOutcome(entry))
            }
        }
        return outcomes
    }

    private static func frameEncodingValidOutcome(
        _ entry: FrameEncodingVectorFixture.Entry
    ) async throws -> VectorOutcome {
        let expectedFrame = try FrameEncodingVectorFixture.frameBytes(for: entry)
        let decoded = try await decodeFrame(expectedFrame)
        guard case .frame(let envelope) = decoded else {
            return VectorOutcome(
                id: entry.id, category: "frame-encoding", outcome: "fail",
                expected: expectedFrame.conformanceRunnerHex,
                actual: "rejected: \(String(describing: decoded))"
            )
        }

        let reencoded = try FrameEncoder.encode(envelope)
        let expectedSha = entry.expected?.frameSha256
        let passed: Bool
        if entry.input.frameHex != nil {
            passed = reencoded == expectedFrame
        } else if let expectedSha {
            passed = expectedSha == frameSha256Hex(reencoded)
        } else {
            passed = true
        }
        let expectedHex = expectedSha ?? expectedFrame.conformanceRunnerHex
        let actualHex = expectedSha != nil ? frameSha256Hex(reencoded) : reencoded.conformanceRunnerHex
        return VectorOutcome(
            id: entry.id, category: "frame-encoding", outcome: passed ? "pass" : "fail",
            expected: expectedHex, actual: actualHex
        )
    }

    private static func frameEncodingInvalidOutcome(
        _ entry: FrameEncodingVectorFixture.Entry
    ) async throws -> VectorOutcome {
        guard let closeCode = entry.closeCode, let localReason = entry.localReason else {
            throw ConformanceFailure(description: "vector \(entry.id) has no closeCode/localReason")
        }
        let frame = try FrameEncodingVectorFixture.frameBytes(for: entry)
        let result = try await decodeFrame(frame)

        let passed: Bool
        let actualDescription: String
        if case .rejected(let code, let reason) = result,
           code == .malformedFrame, frameReasonName(reason) == localReason {
            passed = true
            actualDescription = "MALFORMED_FRAME:\(localReason)"
        } else {
            passed = false
            actualDescription = String(describing: result)
        }
        return VectorOutcome(
            id: entry.id, category: "frame-encoding", outcome: passed ? "pass" : "fail",
            expected: "\(closeCode):\(localReason)", actual: actualDescription
        )
    }

    static func decodeFrame(_ bytes: Data) async throws -> DecodeResult? {
        let pair = InMemoryConnectionPair(bufferCapacity: bytes.count + 8)
        try await pair.endA.send(bytes)
        await pair.endA.close()
        return try await FrameDecoder.decode(from: InMemoryFrameSource(pair.endB))
    }

    static func frameReasonName(_ reason: MalformedFrameReason) -> String {
        switch reason {
        case .tooLarge: return "TOO_LARGE"
        case .badLength: return "BAD_LENGTH"
        case .truncated: return "TRUNCATED"
        case .decodeFailed: return "DECODE_FAILED"
        case .unknownChannel: return "UNKNOWN_CHANNEL"
        case .unknownPayloadType: return "UNKNOWN_PAYLOAD_TYPE"
        case .seqRegression: return "SEQ_REGRESSION"
        case .seqGapTooLarge: return "SEQ_GAP_TOO_LARGE"
        }
    }

    private static func frameSha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).conformanceRunnerHex
    }
}
