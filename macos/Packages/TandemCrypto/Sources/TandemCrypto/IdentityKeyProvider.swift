import Foundation
import Security

/// Fixed Keychain application tag every identity key item is stored under (E10-05, PRD F-1.1).
/// Analogous to the Android identity key's fixed alias `tandem.identity.v1` (E10-01).
public let identityKeyApplicationTag = "com.tandem.identity.v1"

/// Arbitrary, non-secret payload for the sign+verify smoke test below -- never logged or
/// transmitted. Mirrors Android's `IdentityBootstrapper` (E10-04) smoke test.
private let smokeTestPayload = Data("tandem-identity-smoke-test".utf8)

/// ECDSA over a SHA-256 digest, matching the identity key's P-256 curve.
private let smokeTestAlgorithm: SecKeyAlgorithm = .ecdsaSignatureMessageX962SHA256

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

    /// Whether the existing identity key is present and usable, proven with a real sign+verify
    /// smoke test rather than just presence of the item -- the Keychain can retain an item whose
    /// key material is no longer usable (E10-09, mirrors Android's `IdentityBootstrapper`'s
    /// `KeyPermanentlyInvalidatedException` handling, E10-04). Returns `false` (never throws) for
    /// both "no key item exists yet" (`KeychainError.itemNotFound`) and "the item exists but fails
    /// the smoke test" -- `IdentityBootstrapper` treats both the same way (regenerate). Any other
    /// `KeychainError` (e.g. `.authFailed`, `.locked`) is rethrown so the caller can distinguish
    /// "missing/unusable" from "inaccessible" and never treat the latter as a reason to regenerate.
    ///
    /// This is the only place outside `getOrCreateIdentityKey()`'s own callers that touches the raw
    /// `SecKey` -- kept in `TandemCrypto` because the `key_material_only_in_crypto` lint rule
    /// (E10-14) forbids any other module from referencing `SecKey*` directly.
    public func hasUsableIdentityKey() throws -> Bool {
        let key: SecKey
        do {
            key = try keychainStore.copyKey(tag: identityKeyApplicationTag)
        } catch KeychainError.itemNotFound {
            return false
        }
        return Self.smokeTest(key)
    }

    private static func smokeTest(_ key: SecKey) -> Bool {
        guard let publicKey = SecKeyCopyPublicKey(key) else { return false }

        var signError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key, smokeTestAlgorithm, smokeTestPayload as CFData, &signError
        ) else {
            return false
        }

        var verifyError: Unmanaged<CFError>?
        return SecKeyVerifySignature(
            publicKey, smokeTestAlgorithm, smokeTestPayload as CFData, signature, &verifyError
        )
    }
}
