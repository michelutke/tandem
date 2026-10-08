import TandemCrypto

/// Local contacts cache keyed by peer fingerprint (E51-04). Conforms to ``PeerDataPurging`` so
/// unpair removes every contact of the unpaired phone.
public protocol ContactsStore: PeerDataPurging {
    /// Persisted sync watermark, or nil before the first completed sync.
    func watermarkMs(peer: SpkiFingerprint) async throws -> UInt64?

    /// Upserts `contacts` (replacing a contact's numbers and emails), removes
    /// `deletedContactIds`, and stores `watermarkMs` when non-nil, in one transaction.
    func apply(
        peer: SpkiFingerprint,
        contacts: [ContactRecord],
        deletedContactIds: [String],
        watermarkMs: UInt64?
    ) async throws

    /// The contact owning `number`, matching despite formatting differences, or nil.
    func lookup(peer: SpkiFingerprint, number: String) async throws -> ContactRecord?

    /// Ids only -- never a name or number (invariant 7).
    func contactIds(peer: SpkiFingerprint) async throws -> [String]

    /// Every cached contact of `peer`, ordered by contact id.
    func allContacts(peer: SpkiFingerprint) async throws -> [ContactRecord]
}
