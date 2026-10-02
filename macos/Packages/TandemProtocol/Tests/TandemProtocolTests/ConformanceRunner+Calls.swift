import CryptoKit
import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// `calls-encoding` category handler for ``ConformanceRunner`` (E52-01): decodes the raw message
/// bytes each vector describes (`input.messageHex` / `input.messageHexes` -- see
/// `protocol/vectors/README.md`) with the real generated CALLS message types
/// (`protocol/proto/tandem/v1/calls.proto`), selected by `input.kind`.
extension ConformanceRunner {
    static func runCallsEncoding(data: Data) throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(CallsEncodingManifest.self, from: data)
        return try manifest.vectors.map(callsEncodingOutcome)
    }

    private static func callsEncodingOutcome(_ vector: CallsEncodingManifest.Vector) throws -> VectorOutcome {
        switch vector.input.kind {
        case "callEvent": return try callEventOutcome(vector)
        case "callStateSequence": return try callStateSequenceOutcome(vector)
        case "callActionResult": return try callActionResultOutcome(vector)
        default:
            throw ConformanceFailure(description: "unsupported calls-encoding kind: \(vector.input.kind)")
        }
    }

    private static func callsMessageBytes(_ vector: CallsEncodingManifest.Vector) throws -> Data {
        guard let messageHex = vector.input.messageHex else {
            throw ConformanceFailure(description: "calls-encoding vector \(vector.id) missing messageHex")
        }
        return try conformanceRunnerHexDecode(messageHex)
    }

    private static func callsUndecodable(_ vector: CallsEncodingManifest.Vector) -> VectorOutcome {
        VectorOutcome(
            id: vector.id, category: "calls-encoding", outcome: "fail",
            expected: "decodable", actual: "failed to decode"
        )
    }

    private static func callEventOutcome(_ vector: CallsEncodingManifest.Vector) throws -> VectorOutcome {
        let bytes = try callsMessageBytes(vector)
        guard let decoded = try? Tandem_V1_CallEvent(serializedBytes: bytes) else {
            return callsUndecodable(vector)
        }
        guard let expected = vector.expected, let expectedCallId = expected.callId,
              let expectedDirection = expected.direction,
              let expectedDirectionNumber = callDirectionNumbers[expectedDirection],
              let expectedState = expected.state, let expectedStateNumber = callStateNumbers[expectedState],
              let expectedAddress = expected.address, let expectedE164 = expected.normalizedE164,
              let expectedTimestampMs = expected.timestampMs, let expectedSha = expected.messageSha256 else {
            throw ConformanceFailure(description: "calls-encoding vector \(vector.id) missing expected fields")
        }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let reencoded = try? decoded.serializedData()
        let passed = decoded.callID == expectedCallId && decoded.direction.rawValue == expectedDirectionNumber
            && decoded.state.rawValue == expectedStateNumber && decoded.address == expectedAddress
            && decoded.normalizedE164 == expectedE164 && decoded.timestampMs == expectedTimestampMs
            && reencoded == bytes && digest == expectedSha
        return VectorOutcome(
            id: vector.id, category: "calls-encoding", outcome: passed ? "pass" : "fail",
            expected: "callId=\(expectedCallId) state=\(expectedState)",
            actual: "callId=\(decoded.callID) state=\(decoded.state.rawValue)"
        )
    }

    private static func callStateSequenceOutcome(_ vector: CallsEncodingManifest.Vector) throws -> VectorOutcome {
        guard let messageHexes = vector.input.messageHexes else {
            throw ConformanceFailure(description: "calls-encoding vector \(vector.id) missing messageHexes")
        }
        let decoded = try messageHexes.map { try? Tandem_V1_CallEvent(serializedBytes: conformanceRunnerHexDecode($0)) }
        guard decoded.allSatisfy({ $0 != nil }) else {
            return callsUndecodable(vector)
        }
        let events = decoded.compactMap { $0 }
        guard let expected = vector.expected, let expectedCallId = expected.callId,
              let expectedStates = expected.states, let expectedTimestampsMs = expected.timestampsMs else {
            throw ConformanceFailure(description: "calls-encoding vector \(vector.id) missing expected fields")
        }
        let expectedStateNumbers = expectedStates.compactMap { callStateNumbers[$0] }
        let actualStateNumbers = events.map(\.state.rawValue)
        let passed = events.allSatisfy { $0.callID == expectedCallId }
            && expectedStateNumbers.count == expectedStates.count && actualStateNumbers == expectedStateNumbers
            && events.map(\.timestampMs) == expectedTimestampsMs
        return VectorOutcome(
            id: vector.id, category: "calls-encoding", outcome: passed ? "pass" : "fail",
            expected: "callId=\(expectedCallId) states=\(expectedStates)",
            actual: "callIds=\(Set(events.map(\.callID)).sorted()) states=\(actualStateNumbers)"
        )
    }

    private static func callActionResultOutcome(_ vector: CallsEncodingManifest.Vector) throws -> VectorOutcome {
        let bytes = try callsMessageBytes(vector)
        guard let decoded = try? Tandem_V1_CallActionResult(serializedBytes: bytes) else {
            return callsUndecodable(vector)
        }
        guard let expected = vector.expected, let expectedRequestId = expected.requestId,
              let expectedCallId = expected.callId, let expectedSuccess = expected.success,
              let expectedErrorCode = expected.errorCode,
              let expectedErrorNumber = callActionErrorCodeNumbers[expectedErrorCode] else {
            throw ConformanceFailure(description: "calls-encoding vector \(vector.id) missing expected fields")
        }
        let passed = decoded.requestID == expectedRequestId && decoded.callID == expectedCallId
            && decoded.success == expectedSuccess && decoded.errorCode.rawValue == expectedErrorNumber
        return VectorOutcome(
            id: vector.id, category: "calls-encoding", outcome: passed ? "pass" : "fail",
            expected: "requestId=\(expectedRequestId) success=\(expectedSuccess) errorCode=\(expectedErrorCode)",
            actual: "requestId=\(decoded.requestID) success=\(decoded.success) "
                + "errorCode=\(decoded.errorCode.rawValue)"
        )
    }

    /// JSON `CALL_DIRECTION_*` name -> wire number, matching `tools/vectors/calls_encoding.py`.
    static let callDirectionNumbers: [String: Int] = [
        "CALL_DIRECTION_UNSPECIFIED": 0,
        "CALL_DIRECTION_INCOMING": 1,
        "CALL_DIRECTION_OUTGOING": 2
    ]

    /// JSON `CALL_STATE_*` name -> wire number, matching `tools/vectors/calls_encoding.py`.
    static let callStateNumbers: [String: Int] = [
        "CALL_STATE_UNSPECIFIED": 0,
        "CALL_STATE_RINGING": 1,
        "CALL_STATE_DIALING": 2,
        "CALL_STATE_ACTIVE": 3,
        "CALL_STATE_ENDED": 4
    ]

    /// JSON `CALL_ACTION_ERROR_CODE_*` name -> wire number, matching `tools/vectors/calls_encoding.py`.
    static let callActionErrorCodeNumbers: [String: Int] = [
        "CALL_ACTION_ERROR_CODE_UNSPECIFIED": 0,
        "CALL_ACTION_ERROR_CODE_UNKNOWN_CALL": 1,
        "CALL_ACTION_ERROR_CODE_NOT_RINGING": 2,
        "CALL_ACTION_ERROR_CODE_NO_ACTIVE_CALL": 3,
        "CALL_ACTION_ERROR_CODE_PERMISSION_DENIED": 4,
        "CALL_ACTION_ERROR_CODE_INVALID_SUBSCRIPTION": 5,
        "CALL_ACTION_ERROR_CODE_NEEDS_PHONE_TAP": 6,
        "CALL_ACTION_ERROR_CODE_INVALID_NUMBER": 7,
        "CALL_ACTION_ERROR_CODE_RATE_LIMITED": 8
    ]
}

struct CallsEncodingManifest: Decodable {
    struct Input: Decodable {
        let kind: String
        let messageHex: String?
        let messageHexes: [String]?
    }
    struct Expected: Decodable {
        let callId: String?
        let direction: String?
        let state: String?
        let address: String?
        let normalizedE164: String?
        let timestampMs: UInt64?
        let messageSha256: String?
        let states: [String]?
        let timestampsMs: [UInt64]?
        let requestId: String?
        let success: Bool?
        let errorCode: String?
    }
    struct Vector: Decodable {
        let id: String
        let input: Input
        let expected: Expected?
    }
    let vectors: [Vector]
}
