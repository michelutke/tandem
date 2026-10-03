import Foundation
import Testing
import TandemCrypto
import TandemStore
import TandemTestSupport
@testable import TandemTransport

extension RotationInitiatorTests {
    @Test
    func macRotationInitiator_cancel_deletesPendingKeyAndKeepsOldIdentity() throws {
        let harness = try Harness()
        try harness.pair(try Phone())
        let oldSpki = try harness.activeSpki
        try harness.coordinator.begin()

        try harness.coordinator.cancel()

        #expect(try harness.activeSpki == oldSpki)
        #expect(!harness.hasPendingKey)
        #expect(try harness.coordinator.attempt() == nil)
    }

    @Test
    func macRotationInitiator_beginTwice_reusesPendingKey() throws {
        let harness = try Harness()
        try harness.pair(try Phone())

        let first = try harness.coordinator.begin()
        let pendingSpki = try RotationKeyProvider(keychainStore: harness.keychain).getOrCreatePendingSpkiDer()
        let second = try harness.coordinator.begin()

        #expect(first == second)
        #expect(try RotationKeyProvider(keychainStore: harness.keychain).getOrCreatePendingSpkiDer() == pendingSpki)
    }

    @Test
    func macRotationInitiator_restartAfterAllAcked_resumeCompletesSwitch() throws {
        let harness = try Harness()
        let phone = try Phone()
        try harness.pair(phone)
        try harness.coordinator.begin()
        let record = try #require(try harness.trustStore.get(phone.fingerprint))
        try harness.trustStore.unpair(record.fingerprint)

        #expect(try harness.coordinator.resume())

        #expect(!harness.hasPendingKey)
        #expect(try harness.coordinator.attempt() == nil)
    }

    @Test
    func macRotationInitiator_secondRotationAfterFirst_switchesAgain() async throws {
        let harness = try Harness()
        let phone = try Phone()
        try harness.pair(phone)
        try harness.coordinator.begin()
        await Self.rotate(harness, phone).receivedAck()
        let afterFirst = try harness.activeSpki
        try harness.coordinator.begin()
        let initiator = await Self.rotate(harness, phone)
        let sent = try #require(await Self.keyRotation(phone))

        await initiator.receivedAck()

        #expect(try harness.activeSpki == sent.newSpkiDer)
        #expect(try harness.activeSpki != afterFirst)
        #expect(!harness.hasPendingKey)
    }

    @Test
    func macRotationInitiator_pendingKey_storedWithIdentityAccessibility() throws {
        let harness = try Harness()
        try harness.pair(try Phone())

        try harness.coordinator.begin()

        #expect(
            harness.keychain.recordedAccessibility(tag: IdentityKeySlots.secondaryTag)
                == .afterFirstUnlockThisDeviceOnly
        )
    }

    @Test
    func macRotationInitiator_hostedKeychain_newKeyStoredWithOriginalAccessibility() throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.cleanup() }
        let keys = RotationKeyProvider(keychainStore: keychain.store)
        _ = try IdentityKeyProvider(keychainStore: keychain.store).getOrCreateIdentityKey()
        let oldSpki = try keys.activeSpkiDer()
        let pendingSpki = try keys.getOrCreatePendingSpkiDer()
        let pendingTag = try keys.pendingTag()

        try keys.promote(pendingTag: pendingTag)
        try keys.promote(pendingTag: pendingTag)

        #expect(pendingSpki != oldSpki)
        #expect(try keys.activeSpkiDer() == pendingSpki)
        #expect(throws: KeychainError.itemNotFound) {
            _ = try keychain.store.copyKey(tag: identityKeyApplicationTag)
        }
    }
}
