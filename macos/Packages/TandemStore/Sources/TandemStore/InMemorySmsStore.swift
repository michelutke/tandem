import TandemCrypto

/// Dictionary-backed ``SmsStore`` for view-model tests.
public actor InMemorySmsStore: SmsStore {
    private struct PeerData {
        var threads: [Int64: SmsThreadRecord] = [:]
        var messages: [Int64: SmsMessageRecord] = [:]
        var outbound: [String: SmsOutboundRecord] = [:]
        var cursors: SmsSyncCursors?
    }

    private var peers: [SpkiFingerprint: PeerData] = [:]

    public init() {}

    public func threads(peer: SpkiFingerprint) -> [SmsThreadRecord] {
        (peers[peer]?.threads.values.map { $0 } ?? [])
            .sorted { ($0.lastMessageAtMs, $0.threadId) > ($1.lastMessageAtMs, $1.threadId) }
    }

    public func messages(peer: SpkiFingerprint, threadId: Int64) -> [SmsMessageRecord] {
        (peers[peer]?.messages.values.filter { $0.threadId == threadId } ?? [])
            .sorted { ($0.timestampMs, $0.id) < ($1.timestampMs, $1.id) }
    }

    public func outbound(peer: SpkiFingerprint, threadId: Int64) -> [SmsOutboundRecord] {
        (peers[peer]?.outbound.values.filter { $0.threadId == threadId } ?? [])
            .sorted { ($0.timestampMs, $0.clientMessageId) < ($1.timestampMs, $1.clientMessageId) }
    }

    public func cursors(peer: SpkiFingerprint) -> SmsSyncCursors? {
        peers[peer]?.cursors
    }

    public func applyPage(
        peer: SpkiFingerprint,
        threads: [SmsThreadRecord],
        messages: [SmsMessageRecord],
        cursors: SmsSyncCursors
    ) {
        var data = peers[peer] ?? PeerData()
        for thread in threads { data.threads[thread.threadId] = thread }
        for message in messages {
            data.messages[message.id] = message
            data.outbound = data.outbound.filter { $0.value.providerMessageId != message.id }
        }
        data.cursors = cursors
        peers[peer] = data
    }

    public func insertOutbound(peer: SpkiFingerprint, _ record: SmsOutboundRecord) {
        peers[peer, default: PeerData()].outbound[record.clientMessageId] = record
    }

    public func updateOutbound(
        peer: SpkiFingerprint,
        clientMessageId: String,
        state: SmsOutboundState,
        providerMessageId: Int64
    ) {
        guard var record = peers[peer]?.outbound[clientMessageId] else { return }
        record.state = state
        record.providerMessageId = providerMessageId
        peers[peer]?.outbound[clientMessageId] = record
    }

    public func diagnostics(peer: SpkiFingerprint) -> SmsStoreDiagnostics {
        let data = peers[peer] ?? PeerData()
        return SmsStoreDiagnostics(
            threadIds: data.threads.keys.sorted(),
            messageIds: data.messages.keys.sorted(),
            outboundCount: data.outbound.count
        )
    }

    public func purgeAll(peer: SpkiFingerprint) {
        peers[peer] = nil
    }
}
