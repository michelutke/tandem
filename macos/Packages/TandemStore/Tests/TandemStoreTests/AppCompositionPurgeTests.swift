import Foundation
import Testing
import TandemCrypto
import TandemTestSupport
@testable import TandemStore

struct AppCompositionPurgeTests {
    @Test
    func appComposition_unpair_registryPurgesAllStores() async throws {
        let peer = SmsFixtures.peerA
        let directory = try SmsFixtures.makeTempDirectory()
        let smsStore = try GrdbSmsStore.open(at: directory.appendingPathComponent("sms.sqlite"))
        let contactsStore = try GrdbContactsStore.open(at: directory.appendingPathComponent("contacts.sqlite"))
        try await smsStore.applyPage(
            peer: peer,
            threads: [SmsFixtures.thread(1)],
            messages: [SmsFixtures.message(1)],
            cursors: SmsFixtures.cursors
        )
        try await contactsStore.apply(
            peer: peer,
            contacts: [ContactRecord(contactId: "1", displayName: "x", phoneNumbers: [], updatedAtMs: 1)],
            deletedContactIds: [],
            watermarkMs: 1
        )
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let purgeRegistry = PeerDataPurgeRegistry()
        await purgeRegistry.register(smsStore)
        await purgeRegistry.register(contactsStore)

        await UnpairAction.unpair(
            peerSpkiFingerprint: peer,
            session: nil,
            dependencies: .init(
                trustStore: trustStore,
                registry: NoopUnpairRegistry(),
                purgeRegistry: purgeRegistry,
                clock: ManualTestClock()
            )
        )

        #expect(try await smsStore.threads(peer: peer).isEmpty)
        #expect(try await contactsStore.contactIds(peer: peer).isEmpty)
    }
}

private struct NoopUnpairRegistry: UnpairActionRegistry {
    func unregister(_ spkiFingerprint: SpkiFingerprint) async {}
}
