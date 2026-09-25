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

/// File-target coverage (E10-07b, D-75): a throwaway on-disk keychain (`TemporaryKeychain`),
/// never the login keychain, needs no signed host or entitlement -- so these run unconditionally
/// in plain `swift test`, unlike the data-protection-target suite above.
@Suite("SecItemKeychainStore (file target)")
struct SecItemKeychainStoreFileTargetTests {

    @Test
    func secItemKeychainStore_fileTarget_genericPasswordKeyCertificateIdentityRoundTrip() throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.cleanup() }
        let store = keychain.store
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

        let provider = SecIdentityProvider(keychainStore: store)
        let secIdentity = try provider.getOrCreateSecIdentity()
        #expect(sec_identity_create(secIdentity) != nil)
    }

    @Test
    func secItemKeychainStore_fileTarget_listGenericPasswordsReturnsAllAccounts() throws {
        let keychain = try TemporaryKeychain()
        defer { keychain.cleanup() }
        let store = keychain.store
        let service = "com.tandem.test.\(UUID().uuidString)"

        try store.addGenericPassword(
            service: service, account: "a", data: Data("1".utf8), accessibility: .afterFirstUnlockThisDeviceOnly
        )
        try store.addGenericPassword(
            service: service, account: "b", data: Data("2".utf8), accessibility: .afterFirstUnlockThisDeviceOnly
        )

        // Regression: SecItemCopyMatching(kSecMatchLimitAll, kSecReturnData) returns errSecParam
        // (-50) on a file keychain (E10-07b experiment); listGenericPasswords works around it by
        // listing attributes only, then copying each account's data separately.
        let items = try store.listGenericPasswords(service: service)

        #expect(Set(items.map(\.account)) == ["a", "b"])
        #expect(items.first { $0.account == "a" }?.data == Data("1".utf8))
        #expect(items.first { $0.account == "b" }?.data == Data("2".utf8))
    }

    @Test
    func fileKeychain_reopenWithPassword_identitySurvives() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tandem-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("test.keychain-db").path
        let password = UUID().uuidString

        let firstCertificateData: Data = try {
            let fileKeychain = try FileKeychain.createOrOpen(path: path, password: password)
            let store = SecItemKeychainStore(target: .file(fileKeychain))
            let identity = try SecIdentityProvider(keychainStore: store).getOrCreateSecIdentity()
            var certRef: SecCertificate?
            SecIdentityCopyCertificate(identity, &certRef)
            let certificate = try #require(certRef)
            return SecCertificateCopyData(certificate) as Data
        }()

        // Reopens the identical on-disk file (same path, same password) in a fresh `FileKeychain`
        // handle -- the file-keychain equivalent of relaunch persistence (spike E03-02).
        let reopened = try FileKeychain.createOrOpen(path: path, password: password)
        defer { reopened.delete() }
        let reopenedStore = SecItemKeychainStore(target: .file(reopened))
        let reopenedIdentity = try reopenedStore.copyIdentity(keyTag: identityKeyApplicationTag)
        var reopenedCertRef: SecCertificate?
        SecIdentityCopyCertificate(reopenedIdentity, &reopenedCertRef)
        let reopenedCertificate = try #require(reopenedCertRef)
        let secondCertificateData = SecCertificateCopyData(reopenedCertificate) as Data

        #expect(firstCertificateData == secondCertificateData)
    }
}
