import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// `heartbeat` category handler for ``ConformanceRunner`` (E20-01): heartbeat is an empty
/// message on the CONTROL channel, tested similarly to frame-encoding. Round-trips every valid
/// vector through the real `FrameEncoder`/`FrameDecoder` and asserts every invalid vector is
/// rejected with its tagged close code.
extension ConformanceRunner {
    static func runHeartbeat(data: Data) async throws -> [VectorOutcome] {
        let manifest = try HeartbeatVectorFixture.load(from: data)
        var outcomes: [VectorOutcome] = []
        for entry in manifest.vectors {
            if entry.expected != nil {
                outcomes.append(try await heartbeatValidOutcome(entry))
            } else {
                outcomes.append(try await heartbeatInvalidOutcome(entry))
            }
        }
        return outcomes
    }

    private static func heartbeatValidOutcome(
        _ entry: HeartbeatVectorFixture.Entry
    ) async throws -> VectorOutcome {
        let expectedFrame = try HeartbeatVectorFixture.frameBytes(for: entry)
        let decoded = try await decodeFrame(expectedFrame)
        guard case .frame(let envelope) = decoded else {
            return VectorOutcome(
                id: entry.id, category: "heartbeat", outcome: "fail",
                expected: expectedFrame.conformanceRunnerHex,
                actual: "rejected: \(String(describing: decoded))"
            )
        }

        let reencoded = try FrameEncoder.encode(envelope)
        let passed = reencoded == expectedFrame
        return VectorOutcome(
            id: entry.id, category: "heartbeat", outcome: passed ? "pass" : "fail",
            expected: expectedFrame.conformanceRunnerHex,
            actual: reencoded.conformanceRunnerHex
        )
    }

    private static func heartbeatInvalidOutcome(
        _ entry: HeartbeatVectorFixture.Entry
    ) async throws -> VectorOutcome {
        guard let closeCode = entry.closeCode, let localReason = entry.localReason else {
            throw ConformanceFailure(description: "vector \(entry.id) has no closeCode/localReason")
        }
        let frame = try HeartbeatVectorFixture.frameBytes(for: entry)
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
            id: entry.id, category: "heartbeat", outcome: passed ? "pass" : "fail",
            expected: "\(closeCode):\(localReason)", actual: actualDescription
        )
    }

    private static func decodeFrame(_ bytes: Data) async throws -> DecodeResult? {
        let pair = InMemoryConnectionPair(bufferCapacity: bytes.count + 8)
        try await pair.endA.send(bytes)
        await pair.endA.close()
        return try await FrameDecoder.decode(from: InMemoryFrameSource(pair.endB))
    }

    private static func frameReasonName(_ reason: MalformedFrameReason) -> String {
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
}
