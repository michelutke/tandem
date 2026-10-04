import Foundation
import Testing
import TandemCrypto
import TandemProtocol
import TandemStore
@testable import FeatureMessaging

struct ContactsSyncClientTests {
    // swiftlint:disable:next force_try
    private let peer = try! SpkiFingerprint(bytes: Data(repeating: 0xA1, count: SpkiFingerprint.byteCount))

    private func wire(_ id: String, number: String = "") -> Tandem_V1_Contact {
        var contact = Tandem_V1_Contact()
        contact.contactID = id
        contact.displayName = "name-secret-\(id)"
        contact.updatedAtMs = 10
        if !number.isEmpty {
            var phone = Tandem_V1_Contact.PhoneNumber()
            phone.number = number
            contact.phoneNumbers = [phone]
        }
        return contact
    }

    private func response(
        status: Tandem_V1_ContactsSyncStatus = .ok,
        contacts: [Tandem_V1_Contact] = [],
        deleted: [String] = [],
        watermarkMs: UInt64 = 0,
        complete: Bool = true
    ) -> Tandem_V1_ContactsSyncResponse {
        var message = Tandem_V1_ContactsSyncResponse()
        message.status = status
        message.contacts = contacts
        message.deletedContactIds = deleted
        message.watermarkMs = watermarkMs
        message.complete = complete
        return message
    }

    private func sentSinceValues(_ session: FakeTandemSession) async -> [UInt64] {
        await session.sent.compactMap { frame in
            guard frame.channel == .contacts, case .contactsSyncRequest(let request) = frame.payload else { return nil }
            return request.sinceUpdatedAtMs
        }
    }

    @Test
    func contactsSyncClient_sessionReady_requestsSinceStoredWatermark() async throws {
        let session = FakeTandemSession()
        let store = InMemoryContactsStore()
        try await store.apply(peer: peer, contacts: [], deletedContactIds: [], watermarkMs: 1_700_000_000_000)

        try await ContactsSyncClient(peer: peer, session: session, store: store).requestSync()

        #expect(await sentSinceValues(session) == [1_700_000_000_000])
    }

    @Test
    func contactsSyncClient_noStoredWatermark_requestsFullSync() async throws {
        let session = FakeTandemSession()

        try await ContactsSyncClient(peer: peer, session: session, store: InMemoryContactsStore()).requestSync()

        #expect(await sentSinceValues(session) == [0])
    }

    @Test
    func contactsSyncClient_tombstone_removesContactKeepsOthers() async throws {
        let store = InMemoryContactsStore()
        let client = ContactsSyncClient(peer: peer, session: FakeTandemSession(), store: store)
        try await client.handle(response(contacts: [wire("6"), wire("7"), wire("8")]))

        try await client.handle(response(deleted: ["7"]))

        #expect(try await store.contactIds(peer: peer) == ["6", "8"])
    }

    @Test
    func contactsSyncClient_incompletePage_doesNotPersistWatermark() async throws {
        let store = InMemoryContactsStore()
        let client = ContactsSyncClient(peer: peer, session: FakeTandemSession(), store: store)

        try await client.handle(response(contacts: [wire("1")], watermarkMs: 50, complete: false))
        #expect(try await store.watermarkMs(peer: peer) == nil)

        try await client.handle(response(contacts: [wire("2")], watermarkMs: 60, complete: true))
        #expect(try await store.watermarkMs(peer: peer) == 60)
        #expect(try await store.contactIds(peer: peer) == ["1", "2"])
    }

    @Test
    func contactsSyncClient_fullResyncRequired_cacheEqualsFreshSnapshot() async throws {
        let session = FakeTandemSession()
        let store = InMemoryContactsStore()
        let client = ContactsSyncClient(peer: peer, session: session, store: store)
        try await client.handle(response(contacts: [wire("1"), wire("2")], watermarkMs: 100))

        try await client.handle(response(status: .fullResyncRequired))
        #expect(await sentSinceValues(session) == [0])
        #expect(try await store.contactIds(peer: peer).isEmpty)

        try await client.handle(response(contacts: [wire("3"), wire("4")], watermarkMs: 200))
        #expect(try await store.contactIds(peer: peer) == ["3", "4"])
        #expect(try await store.watermarkMs(peer: peer) == 200)
    }

    @Test
    func contactsSyncClient_permissionRequired_leavesCacheUntouched() async throws {
        let store = InMemoryContactsStore()
        let client = ContactsSyncClient(peer: peer, session: FakeTandemSession(), store: store)
        try await client.handle(response(contacts: [wire("1")], watermarkMs: 100))

        try await client.handle(response(status: .permissionRequired))

        #expect(try await store.contactIds(peer: peer) == ["1"])
        #expect(try await store.watermarkMs(peer: peer) == 100)
    }

    @Test
    func contactsSyncClient_oversizedThumbnail_contactRejected() async throws {
        let store = InMemoryContactsStore()
        let client = ContactsSyncClient(peer: peer, session: FakeTandemSession(), store: store)
        var oversized = wire("1")
        oversized.photoThumbnail = Data(count: ContactThumbnailValidator.maxPhotoThumbnailBytes + 1)

        try await client.handle(response(contacts: [oversized, wire("2")]))

        #expect(try await store.contactIds(peer: peer) == ["2"])
    }

    @Test
    func contactsSyncClient_syncedNumber_lookupResolvesContact() async throws {
        let store = InMemoryContactsStore(normalizer: PhoneNumberNormalizer(defaultRegion: "CH"))
        let client = ContactsSyncClient(peer: peer, session: FakeTandemSession(), store: store)

        try await client.handle(response(contacts: [wire("1", number: "+41791234567")]))

        #expect(try await store.lookup(peer: peer, number: "079 123 45 67")?.contactId == "1")
    }
}
