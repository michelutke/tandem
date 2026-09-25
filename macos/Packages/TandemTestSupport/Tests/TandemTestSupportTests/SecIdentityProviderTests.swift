import Foundation
import Testing
import TandemCrypto
@testable import TandemTestSupport

/// E10-07 unit coverage: `SecIdentityProvider` ensures the identity key/certificate exist through
/// `IdentityCertProvider` (which itself ensures the key via `IdentityKeyProvider`, both
/// `KeychainStore`-backed, E10-16) before ever reaching the real-Keychain-only
/// `SecItemCopyMatching(kSecClassIdentity)` step, so this runs against `InMemoryKeychainStore` --
/// an injected `KeychainError` here proves the failure surfaces before that step is ever reached.
/// The identity-construction step itself is a hosted `integration:` test in TandemCryptoTests
/// against `SecItemKeychainStore` (gated behind `TANDEM_KEYCHAIN_INTEGRATION_TESTS`).
@Suite("SecIdentityProvider")
struct SecIdentityProviderTests {

    @Test
    func getOrCreateSecIdentity_keychainStoreThrows_propagatesKeychainError() {
        let store = InMemoryKeychainStore()
        store.failNextOperation(with: .locked)
        let provider = SecIdentityProvider(keychainStore: store)

        #expect(throws: KeychainError.locked) {
            try provider.getOrCreateSecIdentity()
        }
    }
}
