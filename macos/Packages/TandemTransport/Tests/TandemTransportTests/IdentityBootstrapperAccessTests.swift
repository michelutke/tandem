import Foundation
import Security
import Testing
import TandemCrypto
import TandemStore
import TandemTestSupport
@testable import TandemTransport

struct IdentityBootstrapperAccessTests {
    private final class ResetRecorder: @unchecked Sendable {
        var resets = 0
    }

    private static func store(withKey: Bool) throws -> InMemoryKeychainStore {
        let store = InMemoryKeychainStore()
        if withKey {
            _ = try store.addKey(tag: identityKeyApplicationTag, accessibility: .afterFirstUnlockThisDeviceOnly)
        }
        return store
    }

    @Test(arguments: [
        KeychainError.authFailed, .locked, .unhandled(status: errSecUserCanceled),
        .unhandled(status: errSecAllocate), .unhandled(status: errSecIO), .unhandled(status: errSecDecode)
    ])
    func bootstrapIdentity_smokeTestAccessFailure_surfacesErrorAndKeepsKey(failure: KeychainError) throws {
        let store = try Self.store(withKey: true)
        let recorder = ResetRecorder()
        let bootstrapper = IdentityBootstrapper(
            keychainStore: store,
            onIdentityReset: { recorder.resets += 1 },
            smokeTest: { _ in throw failure }
        )

        let state = bootstrapper.bootstrapIdentity()

        guard case .error = state else {
            Issue.record("expected .error, got \(state)")
            return
        }
        #expect((try? store.copyKey(tag: identityKeyApplicationTag)) != nil)
        #expect(!bootstrapper.requiresRePair)
        #expect(recorder.resets == 0)
    }

    @Test func bootstrapIdentity_lookupAuthFailure_surfacesErrorAndKeepsKey() throws {
        let store = try Self.store(withKey: true)
        let bootstrapper = IdentityBootstrapper(keychainStore: store)
        store.failNextOperation(with: .authFailed)

        let state = bootstrapper.bootstrapIdentity()

        guard case .error = state else {
            Issue.record("expected .error, got \(state)")
            return
        }
        #expect((try? store.copyKey(tag: identityKeyApplicationTag)) != nil)
        #expect(!bootstrapper.requiresRePair)
    }

    @Test func bootstrapIdentity_freshInstall_generatesWithoutRePairNotice() throws {
        let store = try Self.store(withKey: false)
        let recorder = ResetRecorder()
        let bootstrapper = IdentityBootstrapper(keychainStore: store, onIdentityReset: { recorder.resets += 1 })

        _ = bootstrapper.bootstrapIdentity()

        #expect((try? store.copyKey(tag: identityKeyApplicationTag)) != nil)
        #expect(!bootstrapper.requiresRePair)
        #expect(recorder.resets == 0)
    }

    @Test func bootstrapIdentity_invalidSignatureWithPriorKey_regeneratesAndShowsNotice() throws {
        let store = try Self.store(withKey: true)
        let recorder = ResetRecorder()
        let bootstrapper = IdentityBootstrapper(
            keychainStore: store,
            onIdentityReset: { recorder.resets += 1 },
            smokeTest: { _ in false }
        )

        _ = bootstrapper.bootstrapIdentity()

        #expect(bootstrapper.requiresRePair)
        #expect(recorder.resets == 1)
    }

    private static func seedPeer(_ store: InMemoryKeychainStore) throws -> TrustStore {
        let trustStore = TrustStore(keychainStore: store)
        try trustStore.put(
            PeerRecord(
                fingerprint: try SpkiFingerprint(bytes: Data(repeating: 0x31, count: SpkiFingerprint.byteCount)),
                displayName: "Pixel 8",
                pairedAt: Date(timeIntervalSince1970: 0),
                lastSeen: Date(timeIntervalSince1970: 0),
                capabilities: []
            )
        )
        return trustStore
    }

    @Test func identityBootstrapper_identityReset_trustStoreEmptied() throws {
        let store = try Self.store(withKey: true)
        let trustStore = try Self.seedPeer(store)
        let bootstrapper = IdentityBootstrapper(keychainStore: store, smokeTest: { _ in false })

        _ = bootstrapper.bootstrapIdentity()

        #expect(bootstrapper.requiresRePair)
        #expect(try trustStore.list().isEmpty)
    }

    @Test func identityBootstrapper_keychainAccessFailure_peerRecordsKept() throws {
        let store = try Self.store(withKey: true)
        let trustStore = try Self.seedPeer(store)
        let bootstrapper = IdentityBootstrapper(keychainStore: store, smokeTest: { _ in throw KeychainError.locked })

        _ = bootstrapper.bootstrapIdentity()

        #expect(try trustStore.list().count == 1)
    }
}
