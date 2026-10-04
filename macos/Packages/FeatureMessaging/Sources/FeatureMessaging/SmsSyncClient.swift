import Foundation
import TandemCrypto
import TandemProtocol
import TandemStore

/// Mirrors the phone's SMS store onto the Mac (E50-14, SPEC § SMS channel). Requests a sync with
/// the persisted cursors, applies each page and its cursors in one store transaction, and
/// reconciles optimistic sends from `SendSmsStatus`. Message content is never logged (invariant 7).
public actor SmsSyncClient {
    public enum SyncStatus: Sendable, Equatable {
        case syncing
        case complete
        case permissionRequired
    }

    public private(set) var syncStatus: SyncStatus = .syncing
    public private(set) var simList: Tandem_V1_SimList?

    private var sendErrorCodes: [String: Tandem_V1_SendSmsErrorCode] = [:]

    private let peer: SpkiFingerprint
    private let store: any SmsStore
    private let session: any TandemSession

    public init(peer: SpkiFingerprint, store: any SmsStore, session: any TandemSession) {
        self.peer = peer
        self.store = store
        self.session = session
    }

    /// Sends `SmsSyncRequest{sinceId, backfillBeforeId}` from the stored cursors (0/0 when empty).
    public func requestSync() async {
        let cursors = try? await store.cursors(peer: peer)
        var request = Tandem_V1_SmsSyncRequest()
        request.sinceID = UInt64(cursors?.highWatermarkId ?? 0)
        request.backfillBeforeID = UInt64(cursors?.backfillCursorId ?? 0)
        syncStatus = .syncing
        try? await session.send(.sms, payload: .smsSyncRequest(request))
    }

    /// Applies one page. Unset cursor fields (an unsolicited push) leave the stored value unchanged;
    /// a store write failure leaves both cursors at their previous values.
    public func handle(_ response: Tandem_V1_SmsSyncResponse) async {
        guard response.status == .ok else {
            if response.status == .permissionRequired { syncStatus = .permissionRequired }
            return
        }
        guard let previous = try? await store.cursors(peer: peer) else { return await applyFirstPage(response) }
        await apply(response, previous: previous)
    }

    public func handle(_ status: Tandem_V1_SendSmsStatus) async {
        guard let state = Self.outboundState(status.state) else { return }
        if state == .failed { sendErrorCodes[status.clientMessageID] = status.errorCode }
        try? await store.updateOutbound(
            peer: peer,
            clientMessageId: status.clientMessageID,
            state: state,
            providerMessageId: Int64(status.providerMessageID)
        )
    }

    public func handle(_ simList: Tandem_V1_SimList) {
        self.simList = simList
    }

    private func applyFirstPage(_ response: Tandem_V1_SmsSyncResponse) async {
        let empty = SmsSyncCursors(highWatermarkId: 0, backfillCursorId: 0, backfillComplete: false)
        await apply(response, previous: empty)
    }

    private func apply(_ response: Tandem_V1_SmsSyncResponse, previous: SmsSyncCursors) async {
        let cursors = SmsSyncCursors(
            highWatermarkId: Self.cursor(response.highWatermarkID, orKeeping: previous.highWatermarkId),
            backfillCursorId: Self.cursor(response.backfillCursorID, orKeeping: previous.backfillCursorId),
            backfillComplete: previous.backfillComplete || response.backfillComplete
        )
        do {
            try await store.applyPage(
                peer: peer,
                threads: response.threads.map(Self.record),
                messages: response.messages.map(Self.record),
                cursors: cursors
            )
        } catch {
            return
        }
        if cursors.backfillComplete {
            syncStatus = .complete
        } else if response.backfillCursorID != 0, cursors != previous {
            await requestSync()
        }
    }

    private static func cursor(_ value: UInt64, orKeeping previous: Int64) -> Int64 {
        value == 0 ? previous : Int64(value)
    }

    private static func record(_ thread: Tandem_V1_SmsThread) -> SmsThreadRecord {
        SmsThreadRecord(
            threadId: Int64(thread.threadID),
            address: thread.address,
            snippet: thread.snippet,
            lastMessageAtMs: Int64(thread.lastMessageAtMs),
            unreadCount: Int32(thread.unreadCount)
        )
    }

    private static func record(_ message: Tandem_V1_SmsMessage) -> SmsMessageRecord {
        SmsMessageRecord(
            id: Int64(message.id),
            threadId: Int64(message.threadID),
            address: message.address,
            body: message.body,
            timestampMs: Int64(message.timestampMs),
            type: Int32(message.type.rawValue),
            subscriptionId: message.subscriptionID,
            deliveryStatus: Int32(message.deliveryStatus.rawValue)
        )
    }

    private static func outboundState(_ state: Tandem_V1_SendSmsState) -> SmsOutboundState? {
        switch state {
        case .sending: .sending
        case .sent: .sent
        case .delivered: .delivered
        case .failed: .failed
        case .unspecified, .UNRECOGNIZED: nil
        }
    }
}

extension SmsSyncClient: ConversationSyncSource {
    public func simOptions() -> [SimOption] {
        (simList?.subscriptions ?? []).map { SimOption(
                id: $0.subscriptionID,
                name: DisplayStringSanitizer.sanitize(Data($0.displayName.utf8), kind: .name)
            ) }
    }

    public func sendErrorCode(clientMessageId: String) -> Tandem_V1_SendSmsErrorCode? {
        sendErrorCodes[clientMessageId]
    }
}
