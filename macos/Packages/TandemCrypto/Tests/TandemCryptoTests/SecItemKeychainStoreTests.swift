import Foundation
import Security
import Testing
@testable import TandemCrypto

/// Manual gate: only runs with `TANDEM_KEYCHAIN_INTEGRATION_TESTS=1` set (see
/// `SecItemKeychainStoreTests`, below).
private let keychainIntegrationTestsEnabled =
    ProcessInfo.processInfo.environment["TANDEM_KEYCHAIN_INTEGRATION_TESTS"] == "1"

/// Real Keychain access needs a signed host with the `keychain-access-groups` entitlement
/// (spike E03-02, docs/spikes/secure-enclave-identity.md) and must never run unattended or touch
/// a developer's real login keychain. Gated behind an explicit opt-in env var; `swift test` never
/// runs this by default.
@Suite("SecItemKeychainStore", .enabled(if: keychainIntegrationTestsEnabled))
struct SecItemKeychainStoreTests {

    @Test
    func secItemKeychainStore_hostedAddThenDelete_copyReturnsItemNotFound() throws {
        let store = SecItemKeychainStore()
        let service = "com.tandem.test.\(UUID().uuidString)"
        let account = "account"
        let data = Data("secret".utf8)

        try store.addGenericPassword(
            service: service,
            account: account,
            data: data,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )
        #expect(try store.copyGenericPassword(service: service, account: account) == data)

        try store.deleteGenericPassword(service: service, account: account)

        #expect(throws: KeychainError.itemNotFound) {
            try store.copyGenericPassword(service: service, account: account)
        }
    }

    @Test
    func identityKey_hostedKeychain_accessibilityReadsAfterFirstUnlockThisDeviceOnly() throws {
        let store = SecItemKeychainStore()
        let provider = IdentityKeyProvider(keychainStore: store)
        defer { try? store.deleteKey(tag: identityKeyApplicationTag) }

        _ = try provider.getOrCreateIdentityKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(identityKeyApplicationTag.utf8),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        #expect(status == errSecSuccess)

        let attributes = result as? [String: Any]
        #expect(
            attributes?[kSecAttrAccessible as String] as? String
                == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        )
    }

    @Test
    func identityKey_hostedKeychainExportPrivateKey_copyExternalRepresentationFails() throws {
        let store = SecItemKeychainStore()
        let provider = IdentityKeyProvider(keychainStore: store)
        defer { try? store.deleteKey(tag: identityKeyApplicationTag) }

        let key = try provider.getOrCreateIdentityKey()

        var error: Unmanaged<CFError>?
        let exported = SecKeyCopyExternalRepresentation(key, &error)
        #expect(exported == nil)
    }
}
