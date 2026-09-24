import Foundation
import Security

/// Production `KeychainStore` (E10-16). The only type in this package that calls
/// `SecItem*`/`SecKey*` -- every other type, including identity storage (E10-05/E10-09) and the
/// trust store (E13-06), reaches the Keychain only through the `KeychainStore` protocol (keeps
/// E10-14's boundary check green). Every item is written to the data-protection keychain
/// (`kSecUseDataProtectionKeychain`) in the app's own access group only.
public struct SecItemKeychainStore: KeychainStore, Sendable {

    public init() {}

    public func addGenericPassword(
        service: String,
        account: String,
        data: Data,
        accessibility: KeychainAccessibility
    ) throws {
        var query = genericPasswordQuery(service: service, account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = accessibility.secAttrAccessible
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    public func copyGenericPassword(service: String, account: String) throws -> Data {
        var query = genericPasswordQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw KeychainError(status) }
        guard let data = result as? Data else { throw KeychainError.itemNotFound }
        return data
    }

    public func updateGenericPassword(service: String, account: String, data: Data) throws {
        let query = genericPasswordQuery(service: service, account: account)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    public func deleteGenericPassword(service: String, account: String) throws {
        let query = genericPasswordQuery(service: service, account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    public func listGenericPasswords(service: String) throws -> [GenericPasswordItem] {
        var query = genericPasswordBaseQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw KeychainError(status) }
        guard let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard
                let account = item[kSecAttrAccount as String] as? String,
                let data = item[kSecValueData as String] as? Data
            else { return nil }
            return GenericPasswordItem(account: account, data: data)
        }
    }

    public func addKey(tag: String, accessibility: KeychainAccessibility) throws -> SecKey {
        let privateKeyAttrs: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: Data(tag.utf8),
            kSecAttrAccessible as String: accessibility.secAttrAccessible
        ]
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecUseDataProtectionKeychain as String: true,
            kSecPrivateKeyAttrs as String: privateKeyAttrs
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw KeychainError(error?.takeRetainedValue())
        }
        return key
    }

    public func copyKey(tag: String) throws -> SecKey {
        var query = keyQuery(tag: tag)
        query[kSecReturnRef as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw KeychainError(status) }
        guard let key = result else { throw KeychainError.itemNotFound }
        // swiftlint:disable:next force_cast
        return (key as! SecKey)
    }

    public func deleteKey(tag: String) throws {
        let query = keyQuery(tag: tag)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    private func genericPasswordBaseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    private func genericPasswordQuery(service: String, account: String) -> [String: Any] {
        var query = genericPasswordBaseQuery(service: service)
        query[kSecAttrAccount as String] = account
        return query
    }

    private func keyQuery(tag: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}

extension KeychainAccessibility {
    var secAttrAccessible: CFString {
        switch self {
        case .afterFirstUnlockThisDeviceOnly: return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }
}

extension KeychainError {
    init(_ status: OSStatus) {
        switch status {
        case errSecInteractionNotAllowed: self = .locked
        case errSecAuthFailed: self = .authFailed
        case errSecItemNotFound: self = .itemNotFound
        case errSecDuplicateItem: self = .duplicateItem
        default: self = .unhandled(status: status)
        }
    }

    init(_ cfError: CFError?) {
        guard let cfError else {
            self = .unhandled(status: errSecParam)
            return
        }
        self = KeychainError(OSStatus(CFErrorGetCode(cfError)))
    }
}
