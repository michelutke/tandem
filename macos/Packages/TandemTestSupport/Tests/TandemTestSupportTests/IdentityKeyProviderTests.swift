import Foundation
import Security
import Testing
import TandemCrypto
@testable import TandemTestSupport

/// E10-05 unit coverage: `IdentityKeyProvider` reaches the Keychain only through `KeychainStore`
/// (E10-16), so these run against `InMemoryKeychainStore`. Real Keychain behaviour is covered by
/// hosted `integration:` tests in TandemCryptoTests against `SecItemKeychainStore`.
@Suite("IdentityKeyProvider")
struct IdentityKeyProviderTests {

    @Test
    func getOrCreateIdentityKey_emptyKeychain_addsOneKeyItemWithFixedTag() throws {
        let store = InMemoryKeychainStore()
        let provider = IdentityKeyProvider(keychainStore: store)

        let created = try provider.getOrCreateIdentityKey()
        let stored = try store.copyKey(tag: identityKeyApplicationTag)

        #expect(store.recordedAccessibility(tag: identityKeyApplicationTag) != nil)
        #expect(try externalRepresentation(stored) == externalRepresentation(created))
    }

    @Test
    func getOrCreateIdentityKey_secondCall_returnsExistingItemWithoutAdd() throws {
        let store = InMemoryKeychainStore()
        let provider = IdentityKeyProvider(keychainStore: store)

        let first = try provider.getOrCreateIdentityKey()
        let second = try provider.getOrCreateIdentityKey()

        #expect(try externalRepresentation(first) == externalRepresentation(second))
    }

    @Test
    func getOrCreateIdentityKey_addRequest_recordsAfterFirstUnlockThisDeviceOnly() throws {
        let store = InMemoryKeychainStore()
        let provider = IdentityKeyProvider(keychainStore: store)

        _ = try provider.getOrCreateIdentityKey()

        #expect(store.recordedAccessibility(tag: identityKeyApplicationTag) == .afterFirstUnlockThisDeviceOnly)
    }
}

private struct ExternalRepresentationFailed: Error {}

private func externalRepresentation(_ key: SecKey) throws -> Data {
    var error: Unmanaged<CFError>?
    guard let data = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
        throw ExternalRepresentationFailed()
    }
    return data
}
