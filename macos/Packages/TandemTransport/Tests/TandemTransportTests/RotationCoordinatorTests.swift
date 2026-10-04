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

    @Test
    func macRotationInitiator_phonePairedAfterBegin_switchWaitsForItsAck() async throws {
        let harness = try Harness()
        let first = try Phone(), second = try Phone()
        try harness.pair(first)
        let oldSpki = try harness.activeSpki
        try harness.coordinator.begin()
        try harness.pair(second)

        await Self.rotate(harness, first).receivedAck()

        #expect(try harness.activeSpki == oldSpki)
        #expect(harness.hasPendingKey)
        let secondInitiator = await Self.rotate(harness, second)
        #expect(await Self.keyRotation(second) != nil)
        await secondInitiator.receivedAck()
        #expect(try harness.activeSpki != oldSpki)
        #expect(!harness.hasPendingKey)
    }

    @Test
    func macRotationInitiator_ackLaterThan30s_ignoredAndOldKeyStaysActive() async throws {
        let harness = try Harness()
        let phone = try Phone()
        try harness.pair(phone)
        let oldSpki = try harness.activeSpki
        try harness.coordinator.begin()
        let initiator = await Self.rotate(harness, phone)
        for _ in 0..<10 { await Task.yield() }

        harness.ackClock.advance(by: RotationInitiator.ackDeadline)
        for _ in 0..<10 { await Task.yield() }
        await initiator.receivedAck()

        #expect(try harness.activeSpki == oldSpki)
        #expect(harness.hasPendingKey)
        #expect(try #require(try harness.coordinator.attempt()).pendingRecordIds.count == 1)
        await Self.rotate(harness, phone).receivedAck()
        #expect(try harness.activeSpki != oldSpki)
    }

    @Test
    func macRotationInitiator_ackWithin30s_switches() async throws {
        let harness = try Harness()
        let phone = try Phone()
        try harness.pair(phone)
        let oldSpki = try harness.activeSpki
        try harness.coordinator.begin()
        let initiator = await Self.rotate(harness, phone)
        for _ in 0..<10 { await Task.yield() }

        harness.ackClock.advance(by: RotationInitiator.ackDeadline - .seconds(1))
        for _ in 0..<10 { await Task.yield() }
        await initiator.receivedAck()

        #expect(try harness.activeSpki != oldSpki)
    }

    @Test
    func macRotationInitiator_pointerLostAfterSwitch_keepsRotatedIdentity() async throws {
        let harness = try Harness()
        let phone = try Phone()
        try harness.pair(phone)
        try harness.coordinator.begin()
        await Self.rotate(harness, phone).receivedAck()
        let rotatedSpki = try harness.activeSpki
        try harness.keychain.deleteGenericPassword(service: "com.tandem.identity.slot.v1", account: "active")

        _ = try IdentityKeyProvider(keychainStore: harness.keychain).getOrCreateIdentityKey()

        #expect(try harness.activeSpki == rotatedSpki)
    }

    @Test
    func macRotationInitiator_pointerCorrupt_fallsBackToSlotHoldingKey() async throws {
        let harness = try Harness()
        let phone = try Phone()
        try harness.pair(phone)
        try harness.coordinator.begin()
        await Self.rotate(harness, phone).receivedAck()
        let rotatedSpki = try harness.activeSpki
        try harness.keychain.updateGenericPassword(
            service: "com.tandem.identity.slot.v1", account: "active", data: Data("garbage".utf8)
        )

        #expect(try harness.activeSpki == rotatedSpki)
    }

    @Test
    func macRotationInitiator_bothSlotsEmpty_generatesUnderPrimary() throws {
        let keychain = InMemoryKeychainStore()

        _ = try IdentityKeyProvider(keychainStore: keychain).getOrCreateIdentityKey()

        #expect(try IdentityKeySlots(keychainStore: keychain).activeTag() == identityKeyApplicationTag)
    }

    @Test
    func macRotationInitiator_identityResetAfterRotation_clearsBothSlots() async throws {
        let harness = try Harness()
        let phone = try Phone()
        try harness.pair(phone)
        try harness.coordinator.begin()
        await Self.rotate(harness, phone).receivedAck()
        try harness.keychain.deleteKey(tag: IdentityKeySlots.secondaryTag)
        _ = try harness.keychain.addKey(tag: identityKeyApplicationTag, accessibility: .afterFirstUnlockThisDeviceOnly)

        IdentityBootstrapper(keychainStore: harness.keychain).bootstrapIdentity()

        #expect((try? harness.keychain.copyKey(tag: identityKeyApplicationTag)) == nil)
    }

    @Test
    func macRotationInitiator_pointerAndPrimaryLostMidAttempt_bootstrapRequiresRePairAndClearsAttempt() throws {
        let harness = try Harness()
        try harness.pair(try Phone())
        try harness.coordinator.begin()
        try harness.keychain.deleteKey(tag: identityKeyApplicationTag)
        try? harness.keychain.deleteGenericPassword(service: "com.tandem.identity.slot.v1", account: "active")
        let bootstrapper = IdentityBootstrapper(keychainStore: harness.keychain)

        bootstrapper.bootstrapIdentity()

        #expect(bootstrapper.requiresRePair)
        #expect(try harness.coordinator.attempt() == nil)
        #expect((try? harness.keychain.copyKey(tag: IdentityKeySlots.secondaryTag)) == nil)
    }

    @Test
    func macRotationInitiator_resumeWithPendingKeyMissing_cancelsAttempt() throws {
        let harness = try Harness()
        try harness.pair(try Phone())
        try harness.coordinator.begin()
        try harness.keychain.deleteKey(tag: IdentityKeySlots.secondaryTag)

        #expect(try !harness.coordinator.resume())

        #expect(try harness.coordinator.attempt() == nil)
    }
}
