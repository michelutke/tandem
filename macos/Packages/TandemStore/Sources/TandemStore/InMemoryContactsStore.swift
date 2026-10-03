import TandemCrypto

/// Dictionary-backed ``ContactsStore`` for view-model tests.
public actor InMemoryContactsStore: ContactsStore {
    private struct PeerData {
        var contacts: [String: ContactRecord] = [:]
        var watermarkMs: UInt64?
    }

    private var peers: [SpkiFingerprint: PeerData] = [:]
    private let normalizer: PhoneNumberNormalizer

    public init(normalizer: PhoneNumberNormalizer = PhoneNumberNormalizer()) {
        self.normalizer = normalizer
    }

    public func watermarkMs(peer: SpkiFingerprint) -> UInt64? {
        peers[peer]?.watermarkMs
    }

    public func apply(
        peer: SpkiFingerprint,
        contacts: [ContactRecord],
        deletedContactIds: [String],
        watermarkMs: UInt64?
    ) {
        var data = peers[peer] ?? PeerData()
        for contact in contacts { data.contacts[contact.contactId] = contact }
        for contactId in deletedContactIds { data.contacts[contactId] = nil }
        if let watermarkMs { data.watermarkMs = watermarkMs }
        peers[peer] = data
    }

    public func lookup(peer: SpkiFingerprint, number: String) -> ContactRecord? {
        let key = normalizer.lookupKey(for: number)
        return (peers[peer]?.contacts.values ?? [:].values)
            .sorted { $0.contactId < $1.contactId }
            .first { contact in
                contact.phoneNumbers.contains {
                    $0.number == number || normalizer.lookupKey(for: $0.number, senderE164: $0.normalizedE164) == key
                }
            }
    }

    public func contactIds(peer: SpkiFingerprint) -> [String] {
        (peers[peer]?.contacts.keys.map { $0 } ?? []).sorted()
    }

    public func purgeAll(peer: SpkiFingerprint) {
        peers[peer] = nil
    }
}
