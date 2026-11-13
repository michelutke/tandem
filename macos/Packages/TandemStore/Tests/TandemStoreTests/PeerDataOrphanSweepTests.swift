import Foundation
import Testing
import TandemCrypto
import TandemTestSupport
@testable import TandemStore

private actor StoredPeersPurger: PeerDataPurging {
    private let stored: [SpkiFingerprint]
    private(set) var purged: [SpkiFingerprint] = []

    init(stored: [SpkiFingerprint]) {
        self.stored = stored
    }

    func storedPeers() async throws -> [SpkiFingerprint] {
        stored
    }

    func purgeAll(peer: SpkiFingerprint) async throws {
        purged.append(peer)
    }
}

private struct UnreadableTrust: Error {}

@Suite("PeerDataOrphanSweep")
struct PeerDataOrphanSweepTests {
    private static func fingerprint(_ byte: UInt8) throws -> SpkiFingerprint {
        try SpkiFingerprint(bytes: Data(repeating: byte, count: SpkiFingerprint.byteCount))
    }

    private static func record(_ fingerprint: SpkiFingerprint) -> PeerRecord {
        PeerRecord(
            fingerprint: fingerprint,
            displayName: "Phone",
            pairedAt: Date(timeIntervalSince1970: 0),
            lastSeen: Date(timeIntervalSince1970: 0),
            capabilities: []
        )
    }

    @Test
    func purgeRegistry_launchWithOrphanedPeerData_purged() async throws {
        let directory = try SmsFixtures.makeTempDirectory()
        let smsStore = try GrdbSmsStore.open(at: directory.appendingPathComponent("sms.sqlite"))
        for peer in [SmsFixtures.peerA, SmsFixtures.peerB] {
            try await smsStore.applyPage(
                peer: peer, threads: [SmsFixtures.thread(1)], messages: [SmsFixtures.message(1)],
                cursors: SmsFixtures.cursors
            )
        }
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        try trustStore.put(Self.record(SmsFixtures.peerA))
        let registry = PeerDataPurgeRegistry(trustedPeers: { try trustStore.pinnedPeers() })

        await registry.register(smsStore)

        #expect(try await smsStore.threads(peer: SmsFixtures.peerB).isEmpty)
        #expect(try await smsStore.threads(peer: SmsFixtures.peerA).count == 1)
    }

    @Test
    func purgeRegistry_orphanSweepContactsStore_onlyUntrustedPeerPurged() async throws {
        let directory = try SmsFixtures.makeTempDirectory()
        let contactsStore = try GrdbContactsStore.open(at: directory.appendingPathComponent("contacts.sqlite"))
        for peer in [SmsFixtures.peerA, SmsFixtures.peerB] {
            try await contactsStore.apply(
                peer: peer,
                contacts: [ContactRecord(contactId: "1", displayName: "x", phoneNumbers: [], updatedAtMs: 1)],
                deletedContactIds: [],
                watermarkMs: 1
            )
        }
        let registry = PeerDataPurgeRegistry(trustedPeers: { [SmsFixtures.peerA] })

        await registry.register(contactsStore)

        #expect(try await contactsStore.contactIds(peer: SmsFixtures.peerB).isEmpty)
        #expect(try await contactsStore.contactIds(peer: SmsFixtures.peerA).count == 1)
    }

    @Test
    func purgeRegistry_orphanSweep_primaryGraceAndRecordIdPinsKept() async throws {
        let (first, second, third, stranger) = (
            try Self.fingerprint(1), try Self.fingerprint(2), try Self.fingerprint(3), try Self.fingerprint(9)
        )
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let original = Self.record(first)
        try trustStore.put(original)
        try trustStore.rotatePrimary(of: original, to: second, now: Date(timeIntervalSince1970: 1))
        let rotated = try #require(try trustStore.list().first)
        try trustStore.rotatePrimary(of: rotated, to: third, now: Date(timeIntervalSince1970: 2))
        let purger = StoredPeersPurger(stored: [first, second, third, stranger])
        let registry = PeerDataPurgeRegistry(trustedPeers: { try trustStore.pinnedPeers() })

        await registry.register(purger)

        #expect(await purger.purged == [stranger])
    }

    @Test
    func purgeRegistry_orphanSweepTrustStoreUnreadable_nothingPurged() async throws {
        let purger = StoredPeersPurger(stored: [try Self.fingerprint(1)])
        let registry = PeerDataPurgeRegistry(trustedPeers: { throw UnreadableTrust() })

        await registry.register(purger)

        #expect(await purger.purged.isEmpty)
    }

    @Test
    func trustStore_pinnedPeersWithCorruptRecord_throwsSoNoSweepRuns() throws {
        let keychain = InMemoryKeychainStore()
        let trustStore = TrustStore(keychainStore: keychain)
        try trustStore.put(Self.record(try Self.fingerprint(1)))
        try keychain.addGenericPassword(
            service: TrustStore.peerRecordService, account: "broken", data: Data([0xFF]),
            accessibility: .afterFirstUnlockThisDeviceOnly
        )

        #expect(throws: (any Error).self) { try trustStore.pinnedPeers() }
    }

    @Test
    func purgeRegistry_withoutTrustedPeersProvider_neverSweeps() async throws {
        let purger = StoredPeersPurger(stored: [try Self.fingerprint(1)])
        let registry = PeerDataPurgeRegistry()

        await registry.register(purger)

        #expect(await purger.purged.isEmpty)
    }
}
