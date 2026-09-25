import Foundation
import Security
import Testing
import TandemCrypto
import X509
@testable import TandemTransport

/// Hosted `unit:` coverage (E10-09) for the paths that need a real `SecIdentity` -- nothing can
/// fake one (spike E03-02, docs/spikes/secure-enclave-identity.md) -- so these run against a
/// throwaway on-disk file keychain (`TemporaryKeychain`, D-75), never the login keychain, and no
/// signed host or entitlement needed. The injected-`KeychainError` paths that never reach a real
/// `SecIdentity` are covered against `InMemoryKeychainStore` in `TandemTestSupportTests`
/// (`IdentityBootstrapperTests`), the only place both `IdentityBootstrapper` (`TandemTransport`)
/// and `InMemoryKeychainStore` (`TandemTestSupport`) are simultaneously available without a
/// package-dependency cycle.
@Suite("IdentityBootstrapper (hosted)")
struct IdentityBootstrapperHostedTests {

    @Test
    func bootstrapIdentity_emptyKeychain_generatesNewIdentity() throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.cleanup() }
        let bootstrapper = IdentityBootstrapper(keychainStore: keychain.store)

        let state = bootstrapper.bootstrapIdentity()

        guard case .ready(let identity) = state else {
            Issue.record("expected .ready, got \(state)")
            return
        }
        #expect(sec_identity_create(identity) != nil)
    }

    @Test
    func bootstrapIdentity_existingIdentity_reusedWithUnchangedFingerprint() throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.cleanup() }
        let first = IdentityBootstrapper(keychainStore: keychain.store)
        guard case .ready = first.bootstrapIdentity() else {
            Issue.record("expected first bootstrap to succeed")
            return
        }
        let firstCertificate = try identityCertificate(over: keychain.store)

        // A new bootstrapper instance over the same store is the relaunch proxy (UC-01).
        let second = IdentityBootstrapper(keychainStore: keychain.store)
        guard case .ready = second.bootstrapIdentity() else {
            Issue.record("expected the relaunch bootstrap to reuse the existing identity")
            return
        }
        let secondCertificate = try identityCertificate(over: keychain.store)

        // Certificate.PublicKey equality is a deterministic proxy for the SPKI fingerprint (the
        // SHA-256 digest of the public key's DER SPKI, E10-08): the same public key always yields
        // the same fingerprint.
        #expect(firstCertificate.publicKey == secondCertificate.publicKey)
        #expect(!second.requiresRePair)
    }

    @Test
    func bootstrapIdentity_injectedItemNotFound_emitsIdentityResetAndRegenerates() throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.cleanup() }
        let first = IdentityBootstrapper(keychainStore: keychain.store)
        guard case .ready = first.bootstrapIdentity() else {
            Issue.record("expected first bootstrap to succeed")
            return
        }
        let originalCertificate = try identityCertificate(over: keychain.store)

        // Deleting the key item behind the bootstrapper's back reproduces the real Keychain
        // returning errSecItemNotFound on the next access -- an "injected" failure via the real
        // Keychain rather than a fake, since this path must reach a real regenerated SecIdentity.
        try keychain.store.deleteKey(tag: identityKeyApplicationTag)

        let recorder = ResetRecorder()
        let second = IdentityBootstrapper(keychainStore: keychain.store, onIdentityReset: { recorder.record() })

        guard case .ready = second.bootstrapIdentity() else {
            Issue.record("expected the regenerated identity to be ready")
            return
        }
        let regeneratedCertificate = try identityCertificate(over: keychain.store)

        #expect(recorder.recordedCount == 1)
        #expect(originalCertificate.publicKey != regeneratedCertificate.publicKey)
        #expect(second.requiresRePair)
    }
}

private func identityCertificate(over store: SecItemKeychainStore) throws -> Certificate {
    try IdentityCertProvider(keychainStore: store).getOrCreateIdentityCertificate()
}

/// Thread-safe reset-callback counter (`IdentityBootstrapper.onIdentityReset` is `@Sendable`, so a
/// captured `var` can't be mutated directly) -- mirrors `ListenerControllerTests`'
/// `RecordingListenerFactory`.
private final class ResetRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func record() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var recordedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
