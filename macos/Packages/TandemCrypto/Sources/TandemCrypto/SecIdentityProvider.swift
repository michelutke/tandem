import Foundation
import Security

/// Combines the Keychain identity certificate (E10-06) and key (E10-05) into a `SecIdentity` for
/// use as the `NWProtocolTLS.Options` local identity (E10-07). Wrapping the result with
/// `sec_identity_create` for `NWProtocolTLS.Options` is left to the caller (E12-01, `TandemTransport`)
/// -- `Network` is the socket-owning module (E00-15's package-graph rule: "only core/transport
/// touches sockets"), so this package, which owns key material (E10-14), never imports it.
///
/// `SecItemCopyMatching(kSecClassIdentity)` pairs a private key with a certificate sharing its
/// public key directly out of Security.framework's own Keychain state -- it is not reachable
/// through `KeychainStore`, and there is no way to fake it, since `SecIdentity` has no public
/// initializer for a synthetic value (spike E03-02, docs/spikes/secure-enclave-identity.md).
/// Ensuring the underlying key and certificate exist goes through `IdentityCertProvider` (E10-06,
/// which itself ensures the key via `IdentityKeyProvider`, E10-05), both `KeychainStore`-backed
/// (E10-16) -- so a failure there is a genuine unit-testable path against `InMemoryKeychainStore`
/// that never reaches the Keychain-dependent step below. The identity-construction step itself is
/// a hosted `integration:` test against `SecItemKeychainStore`, gated behind
/// `TANDEM_KEYCHAIN_INTEGRATION_TESTS`.
public struct SecIdentityProvider: Sendable {

    private let keychainStore: any KeychainStore
    private let dateProvider: @Sendable () -> Date

    public init(keychainStore: any KeychainStore, dateProvider: @escaping @Sendable () -> Date = Date.init) {
        self.keychainStore = keychainStore
        self.dateProvider = dateProvider
    }

    /// Ensures the identity key and self-signed certificate exist, then returns the `SecIdentity`
    /// pairing them.
    public func getOrCreateSecIdentity() throws -> SecIdentity {
        _ = try IdentityCertProvider(
            keychainStore: keychainStore,
            dateProvider: dateProvider
        ).getOrCreateIdentityCertificate()

        return try Self.copySecIdentity(keyTag: identityKeyApplicationTag)
    }

    /// Searches the data-protection keychain for the `SecIdentity` pairing the private key under
    /// `keyTag` with a certificate sharing its public key (both added by `IdentityKeyProvider` /
    /// `IdentityCertProvider` through `SecItemKeychainStore`).
    private static func copySecIdentity(keyTag: String) throws -> SecIdentity {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrApplicationTag as String: Data(keyTag.utf8),
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let result else {
            throw KeychainError(status)
        }
        // swiftlint:disable:next force_cast
        return (result as! SecIdentity)
    }
}
