import Foundation
import Security
import Testing
import TandemCrypto
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

    @Test(arguments: [KeychainError.authFailed, .locked, .unhandled(status: errSecUserCanceled)])
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

    @Test func bootstrapIdentity_missingKey_regeneratesAndRequiresRePair() throws {
        let store = try Self.store(withKey: false)
        let recorder = ResetRecorder()
        let bootstrapper = IdentityBootstrapper(keychainStore: store, onIdentityReset: { recorder.resets += 1 })

        _ = bootstrapper.bootstrapIdentity()

        #expect((try? store.copyKey(tag: identityKeyApplicationTag)) != nil)
        #expect(bootstrapper.requiresRePair)
        #expect(recorder.resets == 1)
    }

    @Test func bootstrapIdentity_invalidSignature_regeneratesAndRequiresRePair() throws {
        let store = try Self.store(withKey: true)
        let bootstrapper = IdentityBootstrapper(keychainStore: store, smokeTest: { _ in false })

        _ = bootstrapper.bootstrapIdentity()

        #expect(bootstrapper.requiresRePair)
    }
}
