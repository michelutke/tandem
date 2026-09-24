import Foundation
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
}
