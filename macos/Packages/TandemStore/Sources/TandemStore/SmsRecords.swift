import Foundation

/// A conversation row mirrored from the phone (`SmsThread`, SPEC § SMS channel). Content fields
/// (`address`, `snippet`) are untrusted peer input and are never logged (invariant 7).
public struct SmsThreadRecord: Sendable, Equatable {
    public let threadId: Int64
    public let address: String
    public let snippet: String
    public let lastMessageAtMs: Int64
    public let unreadCount: Int32

    public init(threadId: Int64, address: String, snippet: String, lastMessageAtMs: Int64, unreadCount: Int32) {
        self.threadId = threadId
        self.address = address
        self.snippet = snippet
        self.lastMessageAtMs = lastMessageAtMs
        self.unreadCount = unreadCount
    }
}

/// A message row mirrored from the phone (`SmsMessage`). `id` is the phone provider `_id`.
public struct SmsMessageRecord: Sendable, Equatable {
    public let id: Int64
    public let threadId: Int64
    public let address: String
    public let body: String
    public let timestampMs: Int64
    public let type: Int32
    public let subscriptionId: Int32
    public let deliveryStatus: Int32

    public init(
        id: Int64,
        threadId: Int64,
        address: String,
        body: String,
        timestampMs: Int64,
        type: Int32,
        subscriptionId: Int32,
        deliveryStatus: Int32
    ) {
        self.id = id
        self.threadId = threadId
        self.address = address
        self.body = body
        self.timestampMs = timestampMs
        self.type = type
        self.subscriptionId = subscriptionId
        self.deliveryStatus = deliveryStatus
    }
}

/// Mac-authoritative sync cursors persisted from the last processed page.
public struct SmsSyncCursors: Sendable, Equatable {
    public let highWatermarkId: Int64
    public let backfillCursorId: Int64
    public let backfillComplete: Bool

    public init(highWatermarkId: Int64, backfillCursorId: Int64, backfillComplete: Bool) {
        self.highWatermarkId = highWatermarkId
        self.backfillCursorId = backfillCursorId
        self.backfillComplete = backfillComplete
    }
}

public enum SmsOutboundState: String, Sendable, Equatable {
    case sending
    case sent
    case delivered
    case failed
}

/// An optimistic outbound row keyed by the Mac-generated `client_message_id`.
public struct SmsOutboundRecord: Sendable, Equatable {
    public let clientMessageId: String
    public let threadId: Int64
    public let address: String
    public let body: String
    public let timestampMs: Int64
    public var state: SmsOutboundState
    public var providerMessageId: Int64

    public init(
        clientMessageId: String,
        threadId: Int64,
        address: String,
        body: String,
        timestampMs: Int64,
        state: SmsOutboundState = .sending,
        providerMessageId: Int64 = 0
    ) {
        self.clientMessageId = clientMessageId
        self.threadId = threadId
        self.address = address
        self.body = body
        self.timestampMs = timestampMs
        self.state = state
        self.providerMessageId = providerMessageId
    }
}

/// Row counts and ids only -- never an address, snippet or body (invariant 7).
public struct SmsStoreDiagnostics: Sendable, Equatable {
    public let threadIds: [Int64]
    public let messageIds: [Int64]
    public let outboundCount: Int

    public var threadCount: Int { threadIds.count }
    public var messageCount: Int { messageIds.count }

    public init(threadIds: [Int64], messageIds: [Int64], outboundCount: Int) {
        self.threadIds = threadIds
        self.messageIds = messageIds
        self.outboundCount = outboundCount
    }
}
