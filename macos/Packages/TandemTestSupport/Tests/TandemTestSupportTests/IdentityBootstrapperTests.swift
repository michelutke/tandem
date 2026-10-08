import Foundation
import Security
import Testing
import TandemCrypto
import TandemTransport
@testable import TandemTestSupport

/// E10-09 unit coverage for the injected-`KeychainError` paths that never need a real
/// `SecIdentity`, so these run against `InMemoryKeychainStore`. This is the only place both
/// `IdentityBootstrapper` (`TandemTransport`) and `InMemoryKeychainStore` (`TandemTestSupport`)
/// are simultaneously available: `TandemTransport` cannot depend on `TandemTestSupport` (it
/// depends on `TandemTransport`, PRD module rules). Paths that need a real `SecIdentity` are
/// covered in `TandemTransportTests`' `IdentityBootstrapperHostedTests` against the D-75 file
/// keychain.
@Suite("IdentityBootstrapper")
struct IdentityBootstrapperTests {

    @Test
    func bootstrapIdentity_afterReset_requiresRePairTrueUntilPairingSucceeds() {
        let store = InMemoryKeychainStore()
        // This Mac generated an identity before (lineage marker present) and its key item is now
        // missing -- errSecItemNotFound -- so this is a genuine reset, not a first generation.
        try? store.addGenericPassword(
            service: "com.tandem.identity.lineage",
            account: "generated",
            data: Data([1]),
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
        let bootstrapper = IdentityBootstrapper(keychainStore: store)

        _ = bootstrapper.bootstrapIdentity()

        #expect(bootstrapper.requiresRePair)

        bootstrapper.notifyPairingSucceeded()

        #expect(!bootstrapper.requiresRePair)
    }

    @Test
    func bootstrapIdentity_injectedAuthFailed_identityErrorStateAndNoFallbackKey() {
        let store = InMemoryKeychainStore()
        store.failNextOperation(with: .authFailed)
        let bootstrapper = IdentityBootstrapper(keychainStore: store)

        let state = bootstrapper.bootstrapIdentity()

        guard case .error = state else {
            Issue.record("expected .error, got \(state)")
            return
        }
        #expect(store.recordedAccessibility(tag: identityKeyApplicationTag) == nil)
        #expect(!bootstrapper.requiresRePair)
    }

    @Test
    func bootstrapIdentity_injectedInteractionNotAllowed_exactlyOneKeychainAttempt() {
        let delegate = InMemoryKeychainStore()
        delegate.failNextOperation(with: .locked)
        let counting = CountingKeychainStore(delegate: delegate)
        let bootstrapper = IdentityBootstrapper(keychainStore: counting)

        let state = bootstrapper.bootstrapIdentity()

        guard case .error = state else {
            Issue.record("expected .error, got \(state)")
            return
        }
        #expect(counting.callCount == 1)
        #expect(!bootstrapper.requiresRePair)
    }
}

/// Counts every `KeychainStore` call made through it, to prove a locked/auth-failed Keychain is
/// read exactly once -- no retry loop (UC-01 alternate flow).
private final class CountingKeychainStore: KeychainStore, @unchecked Sendable {
    private let delegate: any KeychainStore
    private let lock = NSLock()
    private var count = 0

    init(delegate: any KeychainStore) {
        self.delegate = delegate
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    private func counted<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        count += 1
        lock.unlock()
        return try body()
    }

    func addGenericPassword(
        service: String,
        account: String,
        data: Data,
        accessibility: KeychainAccessibility
    ) throws {
        try counted {
            try delegate.addGenericPassword(
                service: service, account: account, data: data, accessibility: accessibility
            )
        }
    }

    func copyGenericPassword(service: String, account: String) throws -> Data {
        try counted { try delegate.copyGenericPassword(service: service, account: account) }
    }

    func updateGenericPassword(service: String, account: String, data: Data) throws {
        try counted { try delegate.updateGenericPassword(service: service, account: account, data: data) }
    }

    func deleteGenericPassword(service: String, account: String) throws {
        try counted { try delegate.deleteGenericPassword(service: service, account: account) }
    }

    func listGenericPasswords(service: String) throws -> [GenericPasswordItem] {
        try counted { try delegate.listGenericPasswords(service: service) }
    }

    func addKey(tag: String, accessibility: KeychainAccessibility) throws -> SecKey {
        try counted { try delegate.addKey(tag: tag, accessibility: accessibility) }
    }

    func copyKey(tag: String) throws -> SecKey {
        try counted { try delegate.copyKey(tag: tag) }
    }

    func deleteKey(tag: String) throws {
        try counted { try delegate.deleteKey(tag: tag) }
    }

    func addCertificate(label: String, der: Data) throws {
        try counted { try delegate.addCertificate(label: label, der: der) }
    }

    func copyCertificate(label: String) throws -> Data {
        try counted { try delegate.copyCertificate(label: label) }
    }

    func deleteCertificate(label: String) throws {
        try counted { try delegate.deleteCertificate(label: label) }
    }

    func copyIdentity(keyTag: String) throws -> SecIdentity {
        try counted { try delegate.copyIdentity(keyTag: keyTag) }
    }
}
