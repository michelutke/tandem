import Foundation
import Security

/// Production `KeychainStore` (E10-16). The only type in this package that calls
/// `SecItem*`/`SecKey*` -- every other type, including identity storage (E10-05/E10-09) and the
/// trust store (E13-06), reaches the Keychain only through the `KeychainStore` protocol (keeps
/// E10-14's boundary check green). Every item is written to `target`'s keychain, in the app's own
/// access group only; production always uses the default `.dataProtection` target, while tests
/// and the E15-22 CI harness pass `.file` (E10-07b, D-75) to use a throwaway on-disk keychain
/// instead, so neither ever touches a developer's login keychain.
public struct SecItemKeychainStore: KeychainStore, Sendable {

    private let target: KeychainTarget

    public init(target: KeychainTarget = .dataProtection) {
        self.target = target
    }

    public func addGenericPassword(
        service: String,
        account: String,
        data: Data,
        accessibility: KeychainAccessibility
    ) throws {
        var query = genericPasswordQuery(service: service, account: account)
        query.merge(target.addAttributes()) { _, new in new }
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = accessibility.secAttrAccessible
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    public func copyGenericPassword(service: String, account: String) throws -> Data {
        var query = genericPasswordQuery(service: service, account: account)
        query.merge(target.searchAttributes()) { _, new in new }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw KeychainError(status) }
        guard let data = result as? Data else { throw KeychainError.itemNotFound }
        return data
    }

    public func updateGenericPassword(service: String, account: String, data: Data) throws {
        var query = genericPasswordQuery(service: service, account: account)
        query.merge(target.searchAttributes()) { _, new in new }
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    public func deleteGenericPassword(service: String, account: String) throws {
        var query = genericPasswordQuery(service: service, account: account)
        query.merge(target.searchAttributes()) { _, new in new }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    /// Lists attributes only (no `kSecReturnData`), then copies each account's data separately:
    /// `SecItemCopyMatching` with `kSecMatchLimitAll` + `kSecReturnData` returns `errSecParam`
    /// (`-50`) on a file keychain (E10-07b experiment), even though it works fine on the
    /// data-protection keychain -- attributes-only listing works identically on both targets.
    public func listGenericPasswords(service: String) throws -> [GenericPasswordItem] {
        var query = genericPasswordBaseQuery(service: service)
        query.merge(target.searchAttributes()) { _, new in new }
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw KeychainError(status) }
        guard let items = result as? [[String: Any]] else { return [] }
        return try items.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String else { return nil }
            let data = try copyGenericPassword(service: service, account: account)
            return GenericPasswordItem(account: account, data: data)
        }
    }

    public func addKey(tag: String, accessibility: KeychainAccessibility) throws -> SecKey {
        let attributes = Self.keyAttributes(tag: tag, accessibility: accessibility, target: target)
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw KeychainError(error?.takeRetainedValue())
        }
        return key
    }

    /// The exact `SecKeyCreateRandomKey` attributes an `addKey` call passes: `target`'s keychain,
    /// the app's own access group only (no `kSecAttrAccessGroup` override), and the requested
    /// tag/accessibility on the private key. Factored out so E10-05's
    /// `usesDataProtectionKeychainOwnGroup` unit test can assert on it (against the default
    /// `.dataProtection` target) without any real Keychain access.
    static func keyAttributes(
        tag: String,
        accessibility: KeychainAccessibility,
        target: KeychainTarget = .dataProtection
    ) -> [String: Any] {
        let privateKeyAttrs: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: Data(tag.utf8),
            kSecAttrAccessible as String: accessibility.secAttrAccessible
        ]
        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: privateKeyAttrs
        ]
        attributes.merge(target.addAttributes()) { _, new in new }
        return attributes
    }

    public func copyKey(tag: String) throws -> SecKey {
        var query = keyQuery(tag: tag)
        query.merge(target.searchAttributes()) { _, new in new }
        query[kSecReturnRef as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw KeychainError(status) }
        guard let key = result else { throw KeychainError.itemNotFound }
        // swiftlint:disable:next force_cast
        return (key as! SecKey)
    }

    public func deleteKey(tag: String) throws {
        var query = keyQuery(tag: tag)
        query.merge(target.searchAttributes()) { _, new in new }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    public func addCertificate(label: String, der: Data) throws {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw KeychainError.unhandled(status: errSecParam)
        }
        var query = certificateQuery(label: label)
        query.merge(target.addAttributes()) { _, new in new }
        query[kSecValueRef as String] = certificate
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    public func copyCertificate(label: String) throws -> Data {
        var query = certificateQuery(label: label)
        query.merge(target.searchAttributes()) { _, new in new }
        query[kSecReturnRef as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw KeychainError(status) }
        guard let result else { throw KeychainError.itemNotFound }
        // swiftlint:disable:next force_cast
        let certificate = (result as! SecCertificate)
        return SecCertificateCopyData(certificate) as Data
    }

    public func deleteCertificate(label: String) throws {
        var query = certificateQuery(label: label)
        query.merge(target.searchAttributes()) { _, new in new }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    /// The `SecIdentity` pairing the private key under `keyTag` with a certificate sharing its
    /// public key -- both added by `IdentityKeyProvider`/`IdentityCertProvider` through this
    /// store (E10-07).
    public func copyIdentity(keyTag: String) throws -> SecIdentity {
        var query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrApplicationTag as String: Data(keyTag.utf8),
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        query.merge(target.searchAttributes()) { _, new in new }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let result else {
            throw KeychainError(status)
        }
        // swiftlint:disable:next force_cast
        return (result as! SecIdentity)
    }

    private func genericPasswordBaseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
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
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom
        ]
    }

    private func certificateQuery(label: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label
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
