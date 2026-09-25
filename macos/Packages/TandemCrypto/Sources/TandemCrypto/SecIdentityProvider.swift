import Foundation
import Security

/// Combines the Keychain identity certificate (E10-06) and key (E10-05) into a `SecIdentity` for
/// use as the `NWProtocolTLS.Options` local identity (E10-07). Wrapping the result with
/// `sec_identity_create` for `NWProtocolTLS.Options` is left to the caller (E12-01, `TandemTransport`)
/// -- `Network` is the socket-owning module (E00-15's package-graph rule: "only core/transport
/// touches sockets"), so this package, which owns key material (E10-14), never imports it.
///
/// `SecItemCopyMatching(kSecClassIdentity)` pairs a private key with a certificate sharing its
/// public key directly out of Security.framework's own Keychain state -- reachable through
/// `KeychainStore.copyIdentity(keyTag:)` (E10-07b), but there is still no way to fake it, since
/// `SecIdentity` has no public initializer for a synthetic value (spike E03-02,
/// docs/spikes/secure-enclave-identity.md); `InMemoryKeychainStore` always throws. Ensuring the
/// underlying key and certificate exist goes through `IdentityCertProvider` (E10-06, which itself
/// ensures the key via `IdentityKeyProvider`, E10-05), both `KeychainStore`-backed (E10-16) -- so
/// a failure there is a genuine unit-testable path against `InMemoryKeychainStore` that never
/// reaches the Keychain-dependent step below. The identity-construction step itself is a hosted
/// `integration:` test against `SecItemKeychainStore` (data-protection target, gated behind
/// `TANDEM_KEYCHAIN_INTEGRATION_TESTS`) and an ungated `unit:` test against a file-target
/// `SecItemKeychainStore` (E10-07b).
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

        return try keychainStore.copyIdentity(keyTag: identityKeyApplicationTag)
    }
}
