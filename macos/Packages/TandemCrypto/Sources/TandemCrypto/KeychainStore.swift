import Foundation
import Security

/// Keychain accessibility class every item is stored under (E10-16, PRD F-1.1 default). Add
/// cases only when a future item genuinely needs a different one.
public enum KeychainAccessibility: Sendable, Equatable {
    case afterFirstUnlockThisDeviceOnly
}

/// Typed failures surfaced by ``KeychainStore``, mapped from the `OSStatus` codes a real Keychain
/// call can return. `SecItemKeychainStore` maps every non-success status through this so a caller
/// never has to branch on raw `OSStatus`; `InMemoryKeychainStore` throws these directly when a
/// test injects one.
public enum KeychainError: Error, Sendable, Equatable {
    /// `errSecInteractionNotAllowed` -- the device is locked.
    case locked
    /// `errSecAuthFailed`.
    case authFailed
    /// `errSecItemNotFound`.
    case itemNotFound
    /// `errSecDuplicateItem`.
    case duplicateItem
    /// Any other non-success `OSStatus`.
    case unhandled(status: OSStatus)
}

/// One generic-password item as returned by ``KeychainStore/listGenericPasswords(service:)``.
public struct GenericPasswordItem: Sendable, Equatable {
    public let account: String
    public let data: Data

    public init(account: String, data: Data) {
        self.account = account
        self.data = data
    }
}

/// Testability seam for Keychain access (E10-16). `SecItemKeychainStore` is the only production
/// type that calls `SecItem*`/`SecKey*` APIs; identity storage (E10-05, E10-09) and the trust
/// store (E13-06) depend on `any KeychainStore` via init, never on Security.framework directly.
/// Unit tests use `InMemoryKeychainStore` (TandemTestSupport), including injected `OSStatus`
/// failures for UC-01 alternate flows; real Keychain behaviour is covered by hosted
/// `integration:` tests against `SecItemKeychainStore`.
public protocol KeychainStore: Sendable {
    /// Generic-password items, keyed by service + account (used by the trust store, E13-06, and
    /// any other Codable record). Throws `KeychainError.duplicateItem` if one already exists.
    func addGenericPassword(
        service: String,
        account: String,
        data: Data,
        accessibility: KeychainAccessibility
    ) throws

    /// Throws `KeychainError.itemNotFound` if none exists.
    func copyGenericPassword(service: String, account: String) throws -> Data

    /// Throws `KeychainError.itemNotFound` if none exists.
    func updateGenericPassword(service: String, account: String, data: Data) throws

    /// Throws `KeychainError.itemNotFound` if none exists.
    func deleteGenericPassword(service: String, account: String) throws

    /// Every generic-password item under `service`, across all accounts.
    func listGenericPasswords(service: String) throws -> [GenericPasswordItem]

    /// A P-256 key item, keyed by application tag (used by identity key storage, E10-05/E10-09).
    /// Generates the key and adds it in one step. Throws `KeychainError.duplicateItem` if a key
    /// already exists under `tag`.
    func addKey(tag: String, accessibility: KeychainAccessibility) throws -> SecKey

    /// Throws `KeychainError.itemNotFound` if none exists.
    func copyKey(tag: String) throws -> SecKey

    /// Throws `KeychainError.itemNotFound` if none exists.
    func deleteKey(tag: String) throws
}
