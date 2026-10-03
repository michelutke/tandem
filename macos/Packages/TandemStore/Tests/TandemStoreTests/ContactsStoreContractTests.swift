import Foundation
import Testing
import TandemCrypto
@testable import TandemStore

private enum ContactsStoreKind: String, CaseIterable, Sendable {
    case inMemory
    case grdb
}

private func makeStore(_ kind: ContactsStoreKind) throws -> any ContactsStore {
    let normalizer = PhoneNumberNormalizer(defaultRegion: "CH")
    switch kind {
    case .inMemory:
        return InMemoryContactsStore(normalizer: normalizer)
    case .grdb:
        let directory = try SmsFixtures.makeTempDirectory()
        return try GrdbContactsStore.open(
            at: directory.appendingPathComponent("contacts.sqlite"), normalizer: normalizer
        )
    }
}

private func contact(_ id: String, numbers: [String] = [], updatedAtMs: Int64 = 1_000) -> ContactRecord {
    ContactRecord(
        contactId: id,
        displayName: "name-secret-\(id)",
        phoneNumbers: numbers.map { ContactPhoneRecord(number: $0) },
        emails: ["mail-secret-\(id)@example.com"],
        photoThumbnail: Data([0xFF, 0xD8]),
        updatedAtMs: updatedAtMs
    )
}

struct ContactsStoreContractTests {
    private let peerA = SmsFixtures.peerA
    private let peerB = SmsFixtures.peerB

    @Test(arguments: ContactsStoreKind.allCases)
    private func contactsCache_deletedContactId_removedFromStore(kind: ContactsStoreKind) async throws {
        let store = try makeStore(kind)
        try await store.apply(
            peer: peerA, contacts: [contact("6"), contact("7"), contact("8")], deletedContactIds: [], watermarkMs: nil
        )
        try await store.apply(peer: peerA, contacts: [], deletedContactIds: ["7"], watermarkMs: nil)

        #expect(try await store.contactIds(peer: peerA) == ["6", "8"])
    }

    @Test(arguments: ContactsStoreKind.allCases)
    private func contactsCache_lookupDifferentlyFormattedEquivalentNumber_resolvesSameContact(
        kind: ContactsStoreKind
    ) async throws {
        let store = try makeStore(kind)
        try await store.apply(
            peer: peerA, contacts: [contact("1", numbers: ["+41791234567"])], deletedContactIds: [], watermarkMs: nil
        )

        #expect(try await store.lookup(peer: peerA, number: "079 123 45 67")?.contactId == "1")
        #expect(try await store.lookup(peer: peerA, number: "+41 79 123 45 67")?.contactId == "1")
        #expect(try await store.lookup(peer: peerA, number: "+41791234567")?.contactId == "1")
    }

    @Test(arguments: ContactsStoreKind.allCases)
    private func contactsCache_lookupStoredNationalFormatByInternationalNumber_resolvesSameContact(
        kind: ContactsStoreKind
    ) async throws {
        let store = try makeStore(kind)
        try await store.apply(
            peer: peerA, contacts: [contact("1", numbers: ["079 123 45 67"])], deletedContactIds: [], watermarkMs: nil
        )

        #expect(try await store.lookup(peer: peerA, number: "+41791234567")?.contactId == "1")
    }

    @Test(arguments: ContactsStoreKind.allCases)
    private func contactsCache_lookupUncachedNumber_returnsNil(kind: ContactsStoreKind) async throws {
        let store = try makeStore(kind)
        try await store.apply(
            peer: peerA, contacts: [contact("1", numbers: ["+41791234567"])], deletedContactIds: [], watermarkMs: nil
        )

        #expect(try await store.lookup(peer: peerA, number: "+41799999999") == nil)
    }

    @Test(arguments: ContactsStoreKind.allCases)
    private func contactsCache_lookupOtherPeersNumber_returnsNil(kind: ContactsStoreKind) async throws {
        let store = try makeStore(kind)
        try await store.apply(
            peer: peerA, contacts: [contact("1", numbers: ["+41791234567"])], deletedContactIds: [], watermarkMs: nil
        )

        #expect(try await store.lookup(peer: peerB, number: "+41791234567") == nil)
    }

    @Test(arguments: ContactsStoreKind.allCases)
    private func contactsCache_contactUpsertedWithNewNumbers_oldNumberNoLongerResolves(
        kind: ContactsStoreKind
    ) async throws {
        let store = try makeStore(kind)
        try await store.apply(
            peer: peerA, contacts: [contact("1", numbers: ["+41791234567"])], deletedContactIds: [], watermarkMs: nil
        )
        try await store.apply(
            peer: peerA, contacts: [contact("1", numbers: ["+41798888888"])], deletedContactIds: [], watermarkMs: nil
        )

        #expect(try await store.lookup(peer: peerA, number: "+41791234567") == nil)
        #expect(try await store.lookup(peer: peerA, number: "+41798888888")?.contactId == "1")
    }

    @Test(arguments: ContactsStoreKind.allCases)
    private func contactsCache_storedContact_roundTripsAllFields(kind: ContactsStoreKind) async throws {
        let store = try makeStore(kind)
        let stored = ContactRecord(
            contactId: "1",
            displayName: "name-secret",
            phoneNumbers: [ContactPhoneRecord(number: "079 123 45 67", normalizedE164: "+41791234567")],
            emails: ["a@example.com", "b@example.com"],
            photoThumbnail: Data([1, 2, 3]),
            updatedAtMs: 42
        )
        try await store.apply(peer: peerA, contacts: [stored], deletedContactIds: [], watermarkMs: nil)

        #expect(try await store.lookup(peer: peerA, number: "+41791234567") == stored)
    }

    @Test(arguments: ContactsStoreKind.allCases)
    private func contactsCache_watermarkApplied_persistedPerPeer(kind: ContactsStoreKind) async throws {
        let store = try makeStore(kind)
        #expect(try await store.watermarkMs(peer: peerA) == nil)

        try await store.apply(peer: peerA, contacts: [], deletedContactIds: [], watermarkMs: 1_700_000_000_000)
        try await store.apply(peer: peerA, contacts: [contact("1")], deletedContactIds: [], watermarkMs: nil)

        #expect(try await store.watermarkMs(peer: peerA) == 1_700_000_000_000)
        #expect(try await store.watermarkMs(peer: peerB) == nil)
    }

    @Test(arguments: ContactsStoreKind.allCases)
    private func contactsStore_peerUnpaired_allRowsForPeerDeleted(kind: ContactsStoreKind) async throws {
        let store = try makeStore(kind)
        try await store.apply(
            peer: peerA, contacts: [contact("1", numbers: ["+41791234567"]), contact("2")],
            deletedContactIds: [], watermarkMs: 5
        )
        try await store.apply(peer: peerB, contacts: [contact("9")], deletedContactIds: [], watermarkMs: 6)

        try await store.purgeAll(peer: peerA)

        #expect(try await store.contactIds(peer: peerA).isEmpty)
        #expect(try await store.watermarkMs(peer: peerA) == nil)
        #expect(try await store.lookup(peer: peerA, number: "+41791234567") == nil)
        #expect(try await store.contactIds(peer: peerB) == ["9"])
        #expect(try await store.watermarkMs(peer: peerB) == 6)
    }
}
