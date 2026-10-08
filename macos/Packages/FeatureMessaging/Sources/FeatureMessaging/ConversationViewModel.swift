import Foundation
import Observation
import TandemCrypto
import TandemProtocol
import TandemStore

enum ConversationSendError: Error {
    case notConnected
}

public enum SendFailure: Sendable, Equatable {
    case noService
    case radioOff
    case permissionRequired
    case invalidAddress
    case tooLong
    case rateLimited
    case subscriptionRequired
    case invalidSubscription
    case generic

    init(_ code: Tandem_V1_SendSmsErrorCode?) {
        switch code {
        case .noService: self = .noService
        case .radioOff: self = .radioOff
        case .permissionRequired: self = .permissionRequired
        case .invalidAddress: self = .invalidAddress
        case .tooLong: self = .tooLong
        case .rateLimited: self = .rateLimited
        case .subscriptionRequired: self = .subscriptionRequired
        case .invalidSubscription: self = .invalidSubscription
        default: self = .generic
        }
    }

    public var reason: String {
        switch self {
        case .noService: "no service"
        case .radioOff: "radio off"
        case .permissionRequired: "SMS permission needed"
        case .invalidAddress: "invalid number"
        case .tooLong: "too long"
        case .rateLimited: "too many sends"
        case .subscriptionRequired: "choose a SIM"
        case .invalidSubscription: "SIM unavailable"
        case .generic: "failed"
        }
    }
}

public enum BubbleState: Sendable, Equatable {
    case received
    case sending
    case sent
    case delivered
    case failed(SendFailure)
}

/// One rendered message. `body` is sanitized peer input and never logged (invariant 7).
public struct MessageBubble: Sendable, Equatable, Identifiable {
    public let id: String
    public let body: String
    public let timestampMs: Int64
    public let isOutbound: Bool
    public let state: BubbleState
}

public struct SimOption: Sendable, Equatable, Identifiable {
    public let id: Int32
    public let name: String
}

/// Where the conversation learns the phone's SIMs and why a send failed (the persisted outbound
/// state alone carries no error code).
public protocol ConversationSyncSource: Sendable {
    func simOptions() async -> [SimOption]
    func sendErrorCode(clientMessageId: String) async -> Tandem_V1_SendSmsErrorCode?
}

/// Drives one conversation (backlog E50-08, PRD F-8.1/F-8.2, UC-18/19): bubbles ascending by
/// timestamp, compose with optimistic `.sending` rows, Retry of failed sends. Never logs
/// addresses or bodies (invariant 7).
@MainActor
@Observable
public final class ConversationViewModel {
    public static let maxBodyLength = 1600

    public let title: String
    public private(set) var bubbles: [MessageBubble] = []
    public private(set) var sims: [SimOption] = []
    public var draft = ""
    public var selectedSubscriptionId: Int32?

    /// The thread's phone number once loaded; handed to the header's call host, never logged.
    public var callAddress: String { address }
    public var showsSimPicker: Bool { sims.count >= 2 }
    public var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ObservationIgnored private let peer: SpkiFingerprint
    @ObservationIgnored private let threadId: Int64
    @ObservationIgnored private let smsStore: any SmsStore
    @ObservationIgnored private let session: (any TandemSession)?
    @ObservationIgnored private let syncSource: any ConversationSyncSource
    @ObservationIgnored private let now: DateProvider
    @ObservationIgnored private let makeClientMessageId: @Sendable () -> String
    private var address = ""
    @ObservationIgnored private var supersededIds: Set<String> = []
    @ObservationIgnored private var failedBodies: [String: String] = [:]

    public init(
        peer: SpkiFingerprint,
        threadId: Int64,
        title: String,
        smsStore: any SmsStore,
        session: (any TandemSession)?,
        syncSource: any ConversationSyncSource,
        now: @escaping DateProvider,
        makeClientMessageId: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.peer = peer
        self.threadId = threadId
        self.title = title
        self.smsStore = smsStore
        self.session = session
        self.syncSource = syncSource
        self.now = now
        self.makeClientMessageId = makeClientMessageId
    }

    public func reload() async {
        let thread = ((try? await smsStore.threads(peer: peer)) ?? []).first { $0.threadId == threadId }
        address = thread?.address ?? address
        sims = await syncSource.simOptions()
        if showsSimPicker, !sims.contains(where: { $0.id == selectedSubscriptionId }) {
            selectedSubscriptionId = sims.first?.id
        }
        let messages = (try? await smsStore.messages(peer: peer, threadId: threadId)) ?? []
        let outbound = ((try? await smsStore.outbound(peer: peer, threadId: threadId)) ?? [])
            .filter { !supersededIds.contains($0.clientMessageId) }
        var built = messages.map(Self.bubble)
        for record in outbound {
            built.append(await bubble(for: record))
        }
        bubbles = built.enumerated()
            .sorted { ($0.element.timestampMs, $0.offset) < ($1.element.timestampMs, $1.offset) }
            .map(\.element)
    }

    public func sendTapped() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        draft = ""
        await send(body: body)
    }

    public func retryTapped(_ bubble: MessageBubble) async {
        guard case .failed = bubble.state, let body = failedBodies[bubble.id] else { return }
        supersededIds.insert(bubble.id)
        await send(body: body)
    }

    private func send(body: String) async {
        if address.isEmpty { await reload() }
        let clientMessageId = makeClientMessageId()
        let timestampMs = Int64(now().timeIntervalSince1970 * 1000)
        try? await smsStore.insertOutbound(
            peer: peer,
            SmsOutboundRecord(
                clientMessageId: clientMessageId,
                threadId: threadId,
                address: address,
                body: body,
                timestampMs: timestampMs
            )
        )
        var request = Tandem_V1_SendSmsRequest()
        request.clientMessageID = clientMessageId
        request.threadID = UInt64(max(threadId, 0))
        request.address = address
        request.subscriptionID = showsSimPicker ? (selectedSubscriptionId ?? 0) : 0
        request.body = body
        await reload()
        do {
            guard let session else { throw ConversationSendError.notConnected }
            try await session.send(.sms, payload: .sendSmsRequest(request))
        } catch {
            try? await smsStore.updateOutbound(
                peer: peer, clientMessageId: clientMessageId, state: .failed, providerMessageId: 0
            )
            await reload()
        }
    }

    private func bubble(for record: SmsOutboundRecord) async -> MessageBubble {
        let state: BubbleState
        switch record.state {
        case .sending: state = .sending
        case .sent: state = .sent
        case .delivered: state = .delivered
        case .failed:
            let code = await syncSource.sendErrorCode(clientMessageId: record.clientMessageId)
            state = .failed(SendFailure(code))
            failedBodies[record.clientMessageId] = record.body
        }
        return MessageBubble(
            id: record.clientMessageId,
            body: Self.sanitize(record.body),
            timestampMs: record.timestampMs,
            isOutbound: true,
            state: state
        )
    }

    private static func bubble(_ message: SmsMessageRecord) -> MessageBubble {
        let inbound = message.type == Int32(Tandem_V1_SmsMessageType.inbox.rawValue)
        return MessageBubble(
            id: "m-\(message.id)",
            body: sanitize(message.body),
            timestampMs: message.timestampMs,
            isOutbound: !inbound,
            state: inbound ? .received : .sent
        )
    }

    private static func sanitize(_ text: String) -> String {
        DisplayStringSanitizer.sanitize(Data(text.utf8), kind: .body)
    }
}
