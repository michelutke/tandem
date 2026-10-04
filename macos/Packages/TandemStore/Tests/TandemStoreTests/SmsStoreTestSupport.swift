import Foundation
import TandemCrypto
@testable import TandemStore

enum SmsFixtures {
    static let peerA = fingerprint(0xA1)
    static let peerB = fingerprint(0xB2)

    static func fingerprint(_ byte: UInt8) -> SpkiFingerprint {
        // swiftlint:disable:next force_try
        try! SpkiFingerprint(bytes: Data(repeating: byte, count: SpkiFingerprint.byteCount))
    }

    static func thread(_ id: Int64, lastMessageAtMs: Int64 = 1_000) -> SmsThreadRecord {
        SmsThreadRecord(
            threadId: id,
            address: "+41790000\(id)",
            snippet: "snippet-secret-\(id)",
            lastMessageAtMs: lastMessageAtMs,
            unreadCount: 1
        )
    }

    static func message(_ id: Int64, thread: Int64 = 1, timestampMs: Int64 = 1_000) -> SmsMessageRecord {
        SmsMessageRecord(
            id: id,
            threadId: thread,
            address: "+41790000\(thread)",
            body: "body-secret-\(id)",
            timestampMs: timestampMs,
            type: 1,
            subscriptionId: 1,
            deliveryStatus: 0
        )
    }

    static let cursors = SmsSyncCursors(highWatermarkId: 10, backfillCursorId: 2, backfillComplete: false)

    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tandem-sms-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
