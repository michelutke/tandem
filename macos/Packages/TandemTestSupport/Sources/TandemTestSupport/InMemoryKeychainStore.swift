import Foundation
import Security
import Synchronization
import TandemCrypto

/// In-memory fake for `KeychainStore` (E10-16). Records every add's accessibility for assertions
/// and supports a one-shot injected `KeychainError`
/// (`.locked`/`.authFailed`/`.itemNotFound`/`.duplicateItem`) to drive UC-01 alternate flows.
/// Key items are generated in-process via `SecKeyCreateRandomKey` with `kSecAttrIsPermanent:
/// false` -- ordinary elliptic-curve crypto, never the Keychain -- so this never touches the real
/// Keychain and never prompts.
public final class InMemoryKeychainStore: KeychainStore, @unchecked Sendable {

    private struct ServiceAccount: Hashable {
        let service: String
        let account: String
    }

    private struct GenericPasswordEntry {
        var data: Data
        var accessibility: KeychainAccessibility
    }

    /// `SecKey` isn't `Sendable`; this box is safe because Security.framework key objects are
    /// documented as thread-safe and this store only ever hands one out immutably.
    private struct KeyBox: @unchecked Sendable {
        let key: SecKey
    }

    private struct KeyEntry {
        var key: KeyBox
        var accessibility: KeychainAccessibility
    }

    private struct State {
        var genericPasswords: [ServiceAccount: GenericPasswordEntry] = [:]
        var keys: [String: KeyEntry] = [:]
        var certificates: [String: Data] = [:]
        var pendingFailure: KeychainError?
    }

    private let state = Mutex(State())

    public init() {}

    /// The next call to any `KeychainStore` method on this store throws `error` instead of
    /// running, then this clears itself.
    public func failNextOperation(with error: KeychainError) {
        state.withLock { $0.pendingFailure = error }
    }

    public func addGenericPassword(
        service: String,
        account: String,
        data: Data,
        accessibility: KeychainAccessibility
    ) throws {
        try consumePendingFailure()
        let key = ServiceAccount(service: service, account: account)
        try state.withLock { state in
            guard state.genericPasswords[key] == nil else { throw KeychainError.duplicateItem }
            state.genericPasswords[key] = GenericPasswordEntry(data: data, accessibility: accessibility)
        }
    }

    public func copyGenericPassword(service: String, account: String) throws -> Data {
        try consumePendingFailure()
        let key = ServiceAccount(service: service, account: account)
        guard let entry = state.withLock({ $0.genericPasswords[key] }) else {
            throw KeychainError.itemNotFound
        }
        return entry.data
    }

    public func updateGenericPassword(service: String, account: String, data: Data) throws {
        try consumePendingFailure()
        let key = ServiceAccount(service: service, account: account)
        try state.withLock { state in
            guard state.genericPasswords[key] != nil else { throw KeychainError.itemNotFound }
            state.genericPasswords[key]?.data = data
        }
    }

    public func deleteGenericPassword(service: String, account: String) throws {
        try consumePendingFailure()
        let key = ServiceAccount(service: service, account: account)
        try state.withLock { state in
            guard state.genericPasswords.removeValue(forKey: key) != nil else {
                throw KeychainError.itemNotFound
            }
        }
    }

    public func listGenericPasswords(service: String) throws -> [GenericPasswordItem] {
        try consumePendingFailure()
        return state.withLock { state in
            state.genericPasswords
                .filter { $0.key.service == service }
                .map { GenericPasswordItem(account: $0.key.account, data: $0.value.data) }
        }
    }

    public func addKey(tag: String, accessibility: KeychainAccessibility) throws -> SecKey {
        try consumePendingFailure()
        guard state.withLock({ $0.keys[tag] }) == nil else { throw KeychainError.duplicateItem }
        let box = KeyBox(key: try Self.generateEphemeralKey())
        state.withLock { $0.keys[tag] = KeyEntry(key: box, accessibility: accessibility) }
        return box.key
    }

    public func copyKey(tag: String) throws -> SecKey {
        try consumePendingFailure()
        guard let entry = state.withLock({ $0.keys[tag] }) else { throw KeychainError.itemNotFound }
        return entry.key.key
    }

    public func deleteKey(tag: String) throws {
        try consumePendingFailure()
        try state.withLock { state in
            guard state.keys.removeValue(forKey: tag) != nil else { throw KeychainError.itemNotFound }
        }
    }

    public func addCertificate(label: String, der: Data) throws {
        try consumePendingFailure()
        try state.withLock { state in
            guard state.certificates[label] == nil else { throw KeychainError.duplicateItem }
            state.certificates[label] = der
        }
    }

    public func copyCertificate(label: String) throws -> Data {
        try consumePendingFailure()
        guard let data = state.withLock({ $0.certificates[label] }) else {
            throw KeychainError.itemNotFound
        }
        return data
    }

    /// Accessibility recorded by the add for this generic-password item, or `nil` if absent.
    public func recordedAccessibility(service: String, account: String) -> KeychainAccessibility? {
        let key = ServiceAccount(service: service, account: account)
        return state.withLock { $0.genericPasswords[key]?.accessibility }
    }

    /// Accessibility recorded by the add for this key item, or `nil` if absent.
    public func recordedAccessibility(tag: String) -> KeychainAccessibility? {
        state.withLock { $0.keys[tag]?.accessibility }
    }

    private func consumePendingFailure() throws {
        let failure = state.withLock { state -> KeychainError? in
            let failure = state.pendingFailure
            state.pendingFailure = nil
            return failure
        }
        if let failure { throw failure }
    }

    private static func generateEphemeralKey() throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: false
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw KeychainError.unhandled(status: errSecParam)
        }
        return key
    }
}
