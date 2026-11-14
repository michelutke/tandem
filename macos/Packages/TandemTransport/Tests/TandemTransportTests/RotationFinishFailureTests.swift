import Foundation
import Synchronization
import Testing
import TandemCrypto
import TandemStore
import TandemTestSupport
@testable import TandemTransport

struct RotationFinishFailureTests {
    @Test
    func rotationCoordinator_finishSwitchThrows_unpairedPhonesStillPurged() throws {
        let keychain = InMemoryKeychainStore()
        let now = Mutex(Date(timeIntervalSince1970: 0))
        let reported = FingerprintLog()
        let trustStore = TrustStore(keychainStore: keychain)
        let coordinator = RotationCoordinator(
            keychainStore: keychain,
            trustStore: trustStore,
            window: RotationInitiatorTests.StubWindow(),
            dateProvider: { now.withLock { $0 } },
            onPeersUnpaired: { reported.append($0) }
        )
        _ = try IdentityKeyProvider(keychainStore: keychain).getOrCreateIdentityKey()
        let phone = try SpkiFingerprint(bytes: Data(repeating: 0x42, count: SpkiFingerprint.byteCount))
        try trustStore.put(PeerRecord(
            fingerprint: phone, displayName: "Phone",
            pairedAt: Date(timeIntervalSince1970: 0), lastSeen: Date(timeIntervalSince1970: 0), capabilities: []
        ))
        try coordinator.begin()
        now.withLock { $0 = Date(timeIntervalSince1970: 0).addingTimeInterval(TrustStore.gracePinLifetime) }
        keychain.failCertificateDeletes(with: .locked)

        #expect(throws: KeychainError.locked) { try coordinator.finish() }

        #expect(reported.values.map(\.hexString) == [phone.hexString])
        #expect(try trustStore.list().isEmpty)
    }
}
