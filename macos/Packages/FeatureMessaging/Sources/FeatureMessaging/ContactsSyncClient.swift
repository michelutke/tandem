import TandemCrypto
import TandemProtocol
import TandemStore

/// Mac side of the CONTACTS channel (E51-04, SPEC § Contacts channel). The composition root calls
/// ``requestSync()`` once the session is Ready and feeds every received `ContactsSyncResponse` to
/// ``handle(_:)``. The watermark is Mac-authoritative: it is persisted only with the last page of
/// a sync. Never logs names or numbers (invariant 7).
public actor ContactsSyncClient {
    private let peer: SpkiFingerprint
    private let session: any TandemSession
    private let store: any ContactsStore

    public init(peer: SpkiFingerprint, session: any TandemSession, store: any ContactsStore) {
        self.peer = peer
        self.session = session
        self.store = store
    }

    /// Sends `ContactsSyncRequest{sinceUpdatedAtMs = stored watermark}`, 0 before the first sync.
    public func requestSync() async throws {
        try await sendRequest(sinceUpdatedAtMs: try await store.watermarkMs(peer: peer) ?? 0)
    }

    public func handle(_ response: Tandem_V1_ContactsSyncResponse) async throws {
        switch response.status {
        case .ok:
            try await store.apply(
                peer: peer,
                contacts: response.contacts.filter(Self.hasValidThumbnail).map(Self.record),
                deletedContactIds: response.deletedContactIds,
                watermarkMs: response.complete ? response.watermarkMs : nil
            )
        case .fullResyncRequired:
            try await store.purgeAll(peer: peer)
            try await sendRequest(sinceUpdatedAtMs: 0)
        default:
            break
        }
    }

    private func sendRequest(sinceUpdatedAtMs: UInt64) async throws {
        var request = Tandem_V1_ContactsSyncRequest()
        request.sinceUpdatedAtMs = sinceUpdatedAtMs
        try await session.send(.contacts, payload: .contactsSyncRequest(request))
    }

    private static func hasValidThumbnail(_ contact: Tandem_V1_Contact) -> Bool {
        ContactThumbnailValidator.isValid(contact.photoThumbnail)
    }

    private static func record(_ contact: Tandem_V1_Contact) -> ContactRecord {
        ContactRecord(
            contactId: contact.contactID,
            displayName: contact.displayName,
            phoneNumbers: contact.phoneNumbers.map {
                ContactPhoneRecord(number: $0.number, normalizedE164: $0.normalizedE164)
            },
            emails: contact.emails.map(\.address),
            photoThumbnail: contact.photoThumbnail,
            updatedAtMs: Int64(clamping: contact.updatedAtMs)
        )
    }
}
