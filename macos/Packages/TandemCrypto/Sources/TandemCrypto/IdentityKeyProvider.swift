import Foundation
import Security

/// Fixed Keychain application tag every identity key item is stored under (E10-05, PRD F-1.1).
/// Analogous to the Android identity key's fixed alias `tandem.identity.v1` (E10-01).
public let identityKeyApplicationTag = "com.tandem.identity.v1"

/// Generates and persists the device's P-256 identity key (E10-05, PRD F-1.1). This is the only
/// key used as the Mac's mTLS local identity (E10-07); certificate issuance over it is E10-06.
/// Reaches the Keychain only through `KeychainStore` (E10-16) -- never `SecItem*`/`SecKey*`
/// directly -- so unit tests run against `InMemoryKeychainStore`; real Keychain behaviour
/// (accessibility, non-extractability, data-protection keychain) is covered by hosted
/// `integration:` tests against `SecItemKeychainStore` (spike E03-02,
/// docs/spikes/secure-enclave-identity.md: needs a signed host with the
/// `keychain-access-groups` entitlement, so those tests are a manual gate, not run by
/// `swift test`).
public struct IdentityKeyProvider: Sendable {

    private let keychainStore: any KeychainStore

    public init(keychainStore: any KeychainStore) {
        self.keychainStore = keychainStore
    }

    /// Returns the existing identity key under the fixed application tag, or generates and
    /// persists one (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, non-synchronizable) if
    /// none exists yet.
    public func getOrCreateIdentityKey() throws -> SecKey {
        do {
            return try keychainStore.copyKey(tag: identityKeyApplicationTag)
        } catch KeychainError.itemNotFound {
            return try keychainStore.addKey(
                tag: identityKeyApplicationTag,
                accessibility: .afterFirstUnlockThisDeviceOnly
            )
        }
    }
}
