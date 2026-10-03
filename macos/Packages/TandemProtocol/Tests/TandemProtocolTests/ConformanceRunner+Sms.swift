import CryptoKit
import Foundation
import TandemTestSupport
@testable import TandemProtocol

/// `sms-encoding` category handler for ``ConformanceRunner`` (E50-01): decodes the raw message
/// bytes each vector describes (`input.messageHex` -- see `protocol/vectors/README.md`) with the
/// real generated SMS message types (`protocol/proto/tandem/v1/sms.proto`), selected by
/// `input.kind`; `smsEnvelopeFrame` instead runs the frame's 4-byte length prefix through the real
/// `FrameDecoder`.
extension ConformanceRunner {
    static func runSmsEncoding(data: Data) async throws -> [VectorOutcome] {
        let manifest = try JSONDecoder().decode(SmsEncodingManifest.self, from: data)
        var outcomes: [VectorOutcome] = []
        for vector in manifest.vectors {
            outcomes.append(try await smsEncodingOutcome(vector))
        }
        return outcomes
    }

    private static func smsEncodingOutcome(_ vector: SmsEncodingManifest.Vector) async throws -> VectorOutcome {
        switch vector.input.kind {
        case "smsMessage": return try smsMessageOutcome(vector)
        case "sendSmsStatus": return try sendSmsStatusOutcome(vector)
        case "smsSyncResponse": return try smsSyncResponseOutcome(vector)
        case "smsEnvelopeFrame": return try await smsEnvelopeFrameOutcome(vector)
        default:
            throw ConformanceFailure(description: "unsupported sms-encoding kind: \(vector.input.kind)")
        }
    }

    private static func messageBytes(_ vector: SmsEncodingManifest.Vector) throws -> Data {
        guard let messageHex = vector.input.messageHex else {
            throw ConformanceFailure(description: "sms-encoding vector \(vector.id) missing messageHex")
        }
        return try conformanceRunnerHexDecode(messageHex)
    }

    private static func undecodable(_ vector: SmsEncodingManifest.Vector) -> VectorOutcome {
        VectorOutcome(
            id: vector.id, category: "sms-encoding", outcome: "fail",
            expected: "decodable", actual: "failed to decode"
        )
    }

    private static func smsMessageOutcome(_ vector: SmsEncodingManifest.Vector) throws -> VectorOutcome {
        let bytes = try messageBytes(vector)
        guard let decoded = try? Tandem_V1_SmsMessage(serializedBytes: bytes) else {
            return undecodable(vector)
        }
        guard let expected = vector.expected, let expectedId = expected.id,
              let expectedThreadId = expected.threadId, let expectedAddress = expected.address,
              let expectedBody = expected.body, let expectedTimestampMs = expected.timestampMs,
              let expectedType = expected.type, let expectedTypeNumber = smsMessageTypeNumbers[expectedType],
              let expectedSubscriptionId = expected.subscriptionId,
              let expectedDeliveryStatus = expected.deliveryStatus,
              let expectedDeliveryNumber = smsDeliveryStatusNumbers[expectedDeliveryStatus],
              let expectedSha = expected.messageSha256 else {
            throw ConformanceFailure(description: "sms-encoding vector \(vector.id) missing expected fields")
        }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let passed = decoded.id == expectedId && decoded.threadID == expectedThreadId
            && decoded.address == expectedAddress && decoded.body == expectedBody
            && decoded.timestampMs == expectedTimestampMs && decoded.type.rawValue == expectedTypeNumber
            && decoded.subscriptionID == expectedSubscriptionId
            && decoded.deliveryStatus.rawValue == expectedDeliveryNumber && digest == expectedSha
        return VectorOutcome(
            id: vector.id, category: "sms-encoding", outcome: passed ? "pass" : "fail",
            expected: "id=\(expectedId) type=\(expectedType)",
            actual: "id=\(decoded.id) type=\(decoded.type.rawValue)"
        )
    }

    private static func sendSmsStatusOutcome(_ vector: SmsEncodingManifest.Vector) throws -> VectorOutcome {
        let bytes = try messageBytes(vector)
        guard let decoded = try? Tandem_V1_SendSmsStatus(serializedBytes: bytes) else {
            return undecodable(vector)
        }
        guard let expected = vector.expected, let expectedClientMessageId = expected.clientMessageId,
              let expectedState = expected.state, let expectedStateNumber = sendSmsStateNumbers[expectedState],
              let expectedErrorCode = expected.errorCode,
              let expectedErrorNumber = sendSmsErrorCodeNumbers[expectedErrorCode],
              let expectedProviderMessageId = expected.providerMessageId else {
            throw ConformanceFailure(description: "sms-encoding vector \(vector.id) missing expected fields")
        }
        let passed = decoded.clientMessageID == expectedClientMessageId
            && decoded.state.rawValue == expectedStateNumber
            && decoded.errorCode.rawValue == expectedErrorNumber
            && decoded.providerMessageID == expectedProviderMessageId
        return VectorOutcome(
            id: vector.id, category: "sms-encoding", outcome: passed ? "pass" : "fail",
            expected: "clientMessageId=\(expectedClientMessageId) state=\(expectedState) "
                + "errorCode=\(expectedErrorCode)",
            actual: "clientMessageId=\(decoded.clientMessageID) state=\(decoded.state.rawValue) "
                + "errorCode=\(decoded.errorCode.rawValue)"
        )
    }

    private static func smsSyncResponseOutcome(_ vector: SmsEncodingManifest.Vector) throws -> VectorOutcome {
        let bytes = try messageBytes(vector)
        guard let decoded = try? Tandem_V1_SmsSyncResponse(serializedBytes: bytes) else {
            return undecodable(vector)
        }
        guard let expected = vector.expected, let expectedStatus = expected.status,
              let expectedStatusNumber = smsSyncStatusNumbers[expectedStatus],
              let expectedThreadCount = expected.threadCount, let expectedMessageIds = expected.messageIds,
              let expectedHighWatermarkId = expected.highWatermarkId,
              let expectedBackfillCursorId = expected.backfillCursorId,
              let expectedBackfillComplete = expected.backfillComplete else {
            throw ConformanceFailure(description: "sms-encoding vector \(vector.id) missing expected fields")
        }
        let actualMessageIds = decoded.messages.map(\.id)
        let passed = decoded.status.rawValue == expectedStatusNumber
            && decoded.threads.count == expectedThreadCount && actualMessageIds == expectedMessageIds
            && decoded.highWatermarkID == expectedHighWatermarkId
            && decoded.backfillCursorID == expectedBackfillCursorId
            && decoded.backfillComplete == expectedBackfillComplete
        return VectorOutcome(
            id: vector.id, category: "sms-encoding", outcome: passed ? "pass" : "fail",
            expected: "status=\(expectedStatus) messageIds=\(expectedMessageIds) "
                + "backfillCursorId=\(expectedBackfillCursorId)",
            actual: "status=\(decoded.status.rawValue) messageIds=\(actualMessageIds) "
                + "backfillCursorId=\(decoded.backfillCursorID)"
        )
    }

    private static func smsEnvelopeFrameOutcome(
        _ vector: SmsEncodingManifest.Vector
    ) async throws -> VectorOutcome {
        guard let frameHex = vector.input.frameHex, let closeCode = vector.closeCode,
              let localReason = vector.localReason else {
            throw ConformanceFailure(description: "sms-encoding vector \(vector.id) missing frame fields")
        }
        let result = try await decodeFrame(try conformanceRunnerHexDecode(frameHex))
        let passed: Bool
        let actualDescription: String
        if case .rejected(let code, let reason) = result,
           code == .malformedFrame, frameReasonName(reason) == localReason {
            passed = true
            actualDescription = "\(closeCode):\(localReason)"
        } else {
            passed = false
            actualDescription = String(describing: result)
        }
        return VectorOutcome(
            id: vector.id, category: "sms-encoding", outcome: passed ? "pass" : "fail",
            expected: "\(closeCode):\(localReason)", actual: actualDescription
        )
    }

    /// JSON `SMS_MESSAGE_TYPE_*` name -> wire number, matching `tools/vectors/sms_encoding.py`.
    static let smsMessageTypeNumbers: [String: Int] = [
        "SMS_MESSAGE_TYPE_UNSPECIFIED": 0,
        "SMS_MESSAGE_TYPE_INBOX": 1,
        "SMS_MESSAGE_TYPE_SENT": 2,
        "SMS_MESSAGE_TYPE_DRAFT": 3,
        "SMS_MESSAGE_TYPE_OUTBOX": 4,
        "SMS_MESSAGE_TYPE_FAILED": 5,
        "SMS_MESSAGE_TYPE_QUEUED": 6
    ]

    /// JSON `SMS_DELIVERY_STATUS_*` name -> wire number, matching `tools/vectors/sms_encoding.py`.
    static let smsDeliveryStatusNumbers: [String: Int] = [
        "SMS_DELIVERY_STATUS_UNSPECIFIED": 0,
        "SMS_DELIVERY_STATUS_PENDING": 1,
        "SMS_DELIVERY_STATUS_COMPLETE": 2,
        "SMS_DELIVERY_STATUS_FAILED": 3
    ]

    /// JSON `SMS_SYNC_STATUS_*` name -> wire number, matching `tools/vectors/sms_encoding.py`.
    static let smsSyncStatusNumbers: [String: Int] = [
        "SMS_SYNC_STATUS_UNSPECIFIED": 0,
        "SMS_SYNC_STATUS_OK": 1,
        "SMS_SYNC_STATUS_PERMISSION_REQUIRED": 2
    ]

    /// JSON `SEND_SMS_STATE_*` name -> wire number, matching `tools/vectors/sms_encoding.py`.
    static let sendSmsStateNumbers: [String: Int] = [
        "SEND_SMS_STATE_UNSPECIFIED": 0,
        "SEND_SMS_STATE_SENDING": 1,
        "SEND_SMS_STATE_SENT": 2,
        "SEND_SMS_STATE_DELIVERED": 3,
        "SEND_SMS_STATE_FAILED": 4
    ]

    /// JSON `SEND_SMS_ERROR_CODE_*` name -> wire number, matching `tools/vectors/sms_encoding.py`.
    static let sendSmsErrorCodeNumbers: [String: Int] = [
        "SEND_SMS_ERROR_CODE_UNSPECIFIED": 0,
        "SEND_SMS_ERROR_CODE_GENERIC_FAILURE": 1,
        "SEND_SMS_ERROR_CODE_NO_SERVICE": 2,
        "SEND_SMS_ERROR_CODE_RADIO_OFF": 3,
        "SEND_SMS_ERROR_CODE_PERMISSION_REQUIRED": 4,
        "SEND_SMS_ERROR_CODE_INVALID_ADDRESS": 5,
        "SEND_SMS_ERROR_CODE_TOO_LONG": 6,
        "SEND_SMS_ERROR_CODE_RATE_LIMITED": 7,
        "SEND_SMS_ERROR_CODE_SUBSCRIPTION_REQUIRED": 8,
        "SEND_SMS_ERROR_CODE_INVALID_SUBSCRIPTION": 9
    ]
}

struct SmsEncodingManifest: Decodable {
    struct Input: Decodable {
        let kind: String
        let messageHex: String?
        let frameHex: String?
    }
    struct Expected: Decodable {
        let id: UInt64?
        let threadId: UInt64?
        let address: String?
        let body: String?
        let timestampMs: UInt64?
        let type: String?
        let subscriptionId: Int32?
        let deliveryStatus: String?
        let messageSha256: String?
        let clientMessageId: String?
        let state: String?
        let errorCode: String?
        let providerMessageId: UInt64?
        let status: String?
        let threadCount: Int?
        let messageIds: [UInt64]?
        let highWatermarkId: UInt64?
        let backfillCursorId: UInt64?
        let backfillComplete: Bool?
    }
    struct Vector: Decodable {
        let id: String
        let input: Input
        let expected: Expected?
        let closeCode: String?
        let localReason: String?
    }
    let vectors: [Vector]
}
