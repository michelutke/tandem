import Foundation
import Observation
import TandemCrypto
import TandemProtocol
import TandemStore

/// One dialable entry of the Calls section: a contact's name with one of their numbers. Both are
/// sanitized peer input and never logged (invariant 7).
public struct CallContactRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let number: String
    public let displayNumber: String
}

/// Drives the Calls section's "Call someone" list (ui-spec §7.1 Calls): every cached contact number
/// of the paired phone, narrowed by a search query over name and digits.
@MainActor
@Observable
public final class CallsSectionViewModel {
    public private(set) var contacts: [CallContactRow] = []
    public var query = ""

    @ObservationIgnored private let peer: SpkiFingerprint
    @ObservationIgnored private let contactsStore: any ContactsStore
    @ObservationIgnored private let numberNormalizer: PhoneNumberNormalizer

    public init(
        peer: SpkiFingerprint,
        contacts: any ContactsStore,
        numberNormalizer: PhoneNumberNormalizer = PhoneNumberNormalizer()
    ) {
        self.peer = peer
        self.contactsStore = contacts
        self.numberNormalizer = numberNormalizer
    }

    public var visibleContacts: [CallContactRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return contacts }
        let digits = trimmed.filter(\.isNumber)
        return contacts.filter { row in
            row.name.localizedCaseInsensitiveContains(trimmed)
                || (!digits.isEmpty && row.number.filter(\.isNumber).contains(digits))
        }
    }

    public func reload() async {
        let records = (try? await contactsStore.allContacts(peer: peer)) ?? []
        contacts = records
            .flatMap { record -> [CallContactRow] in
                let name = DisplayStringSanitizer.sanitize(Data(record.displayName.utf8), kind: .name)
                return record.phoneNumbers.map { phone in
                    CallContactRow(
                        id: "\(record.contactId)|\(phone.number)",
                        name: name,
                        number: phone.number,
                        displayNumber: numberNormalizer.internationalFormat(of: phone.number) ?? phone.number
                    )
                }
            }
            .sorted { ($0.name.localizedLowercase, $0.number) < ($1.name.localizedLowercase, $1.number) }
    }
}
