import Foundation
import TandemCrypto
import TandemStore
import Testing
@testable import FeatureCalls

@MainActor
@Suite struct CallsSectionViewModelTests {
    // swiftlint:disable:next force_try
    private let peer = try! SpkiFingerprint(bytes: Data(repeating: 0x07, count: SpkiFingerprint.byteCount))

    private func makeModel(contacts: [ContactRecord]) async -> CallsSectionViewModel {
        let store = InMemoryContactsStore(normalizer: PhoneNumberNormalizer(defaultRegion: "CH"))
        await store.apply(peer: peer, contacts: contacts, deletedContactIds: [], watermarkMs: nil)
        let model = CallsSectionViewModel(
            peer: peer, contacts: store, numberNormalizer: PhoneNumberNormalizer(defaultRegion: "CH")
        )
        await model.reload()
        return model
    }

    private func contact(_ id: String, _ name: String, _ numbers: [String]) -> ContactRecord {
        ContactRecord(
            contactId: id,
            displayName: name,
            phoneNumbers: numbers.map { ContactPhoneRecord(number: $0) },
            updatedAtMs: 1
        )
    }

    @Test func callsSection_contactsWithTwoNumbers_oneRowPerNumberSortedByName() async {
        let model = await makeModel(contacts: [
            contact("2", "Nina", ["+41792341108", "+41445552010"]),
            contact("1", "Mum", ["+41791112233"])
        ])
        #expect(model.contacts.map(\.name) == ["Mum", "Nina", "Nina"])
        #expect(model.contacts.first?.displayNumber == "+41 79 111 22 33")
    }

    @Test func callsSection_searchByNameAndDigits_narrowsRows() async {
        let model = await makeModel(contacts: [
            contact("2", "Nina Brunner", ["+41792341108"]),
            contact("1", "Mum", ["+41791112233"])
        ])
        model.query = "nina"
        #expect(model.visibleContacts.map(\.name) == ["Nina Brunner"])
        model.query = "1112233"
        #expect(model.visibleContacts.map(\.name) == ["Mum"])
        model.query = "zzz"
        #expect(model.visibleContacts.isEmpty)
        model.query = ""
        #expect(model.visibleContacts.count == 2)
    }

    @Test func callsSection_noContacts_isEmpty() async {
        let model = await makeModel(contacts: [])
        #expect(model.visibleContacts.isEmpty)
    }
}
