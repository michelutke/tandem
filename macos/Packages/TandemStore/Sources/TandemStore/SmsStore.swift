import TandemCrypto

/// Local SMS persistence keyed by peer fingerprint (E50-09). Conforms to ``PeerDataPurging`` so
/// unpair removes every row of the unpaired phone.
public protocol SmsStore: PeerDataPurging {
    /// Threads of `peer`, most recent first.
    func threads(peer: SpkiFingerprint) async throws -> [SmsThreadRecord]

    /// Messages of one thread, ascending by timestamp then id.
    func messages(peer: SpkiFingerprint, threadId: Int64) async throws -> [SmsMessageRecord]

    /// Optimistic outbound rows of one thread, ascending by timestamp.
    func outbound(peer: SpkiFingerprint, threadId: Int64) async throws -> [SmsOutboundRecord]

    /// Persisted cursors, or nil before the first processed page.
    func cursors(peer: SpkiFingerprint) async throws -> SmsSyncCursors?

    /// Upserts threads and messages and stores `cursors` in one transaction. A message whose id
    /// equals an outbound row's `providerMessageId` replaces that optimistic row.
    func applyPage(
        peer: SpkiFingerprint,
        threads: [SmsThreadRecord],
        messages: [SmsMessageRecord],
        cursors: SmsSyncCursors
    ) async throws

    func insertOutbound(peer: SpkiFingerprint, _ record: SmsOutboundRecord) async throws

    /// No-op when no row has `clientMessageId`.
    func updateOutbound(
        peer: SpkiFingerprint,
        clientMessageId: String,
        state: SmsOutboundState,
        providerMessageId: Int64
    ) async throws

    func diagnostics(peer: SpkiFingerprint) async throws -> SmsStoreDiagnostics
}
