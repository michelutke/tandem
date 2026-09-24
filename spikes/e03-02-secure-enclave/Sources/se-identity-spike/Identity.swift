import Foundation
import Security
import CryptoKit

enum IdentityError: Error, CustomStringConvertible {
    case keyGenerationFailed(OSStatus, CFError?)
    case noPublicKey
    case publicKeyExportFailed(CFError?)
    case signingFailed(CFError?)
    case certificateCreationFailed
    case keychainAddFailed(String, OSStatus)
    case identityLookupFailed(OSStatus)

    var description: String {
        switch self {
        case .keyGenerationFailed(let status, let err):
            return "SecKeyCreateRandomKey failed: OSStatus=\(status) (\(secErrorMessage(status))) cferror=\(String(describing: err))"
        case .noPublicKey: return "SecKeyCopyPublicKey returned nil"
        case .publicKeyExportFailed(let err): return "SecKeyCopyExternalRepresentation (public) failed: \(String(describing: err))"
        case .signingFailed(let err): return "SecKeyCreateSignature failed: \(String(describing: err))"
        case .certificateCreationFailed: return "SecCertificateCreateWithData returned nil"
        case .keychainAddFailed(let item, let status): return "SecItemAdd(\(item)) failed: OSStatus=\(status) (\(secErrorMessage(status)))"
        case .identityLookupFailed(let status): return "SecItemCopyMatching(kSecClassIdentity) failed: OSStatus=\(status) (\(secErrorMessage(status)))"
        }
    }
}

func secErrorMessage(_ status: OSStatus) -> String {
    (SecCopyErrorMessageString(status, nil) as String?) ?? "unknown"
}

enum KeyBacking: String { case secureEnclave, software }

struct GeneratedIdentity {
    let label: String
    let backing: KeyBacking
    let privateKey: SecKey
    let certificate: SecCertificate
    let secIdentity: SecIdentity
    let spkiSha256: Data
}

/// Fixed ASN.1 DER prefix for a SubjectPublicKeyInfo wrapping an uncompressed P-256 EC public
/// key (id-ecPublicKey / prime256v1), used only to compute the SPKI-SHA256 fingerprint we log
/// -- the certificate itself is built independently in DER.swift.
private let p256SPKIPrefix: [UInt8] = [
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
    0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00
]

func spkiSha256(rawPoint: [UInt8]) -> Data {
    Data(SHA256.hash(data: Data(p256SPKIPrefix) + Data(rawPoint)))
}

/// A throwaway, on-disk keychain file created fresh for this process and deleted by
/// `cleanup()`. Never the login/default keychain -- this is the only keychain the "legacy"
/// (non-data-protection) code path in `generateIdentity` is allowed to write to.
final class TemporaryKeychain {
    let url: URL
    private(set) var keychain: SecKeychain?
    private let password: String

    /// Creates a brand new, empty keychain file at a fresh temp path.
    convenience init() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("se-identity-spike-\(UUID().uuidString)")
        try self.init(directory: dir, password: UUID().uuidString, create: true)
    }

    /// Creates (or reopens, for the `relaunch-check` experiment) a keychain file at a
    /// caller-chosen path with a caller-chosen password, so a second process invocation can
    /// unlock the same on-disk file to test persistence across relaunch. Still never the login
    /// keychain -- always a path under `directory`, which the caller owns and deletes.
    init(directory: URL, password: String, create: Bool) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent("spike.keychain-db")
        self.password = password
        var kc: SecKeychain?
        let status: OSStatus
        if create {
            status = SecKeychainCreate(url.path, UInt32(password.utf8.count), password, false, nil, &kc)
        } else {
            status = SecKeychainOpen(url.path, &kc)
        }
        guard status == errSecSuccess, let opened = kc else {
            throw IdentityError.keychainAddFailed(create ? "SecKeychainCreate" : "SecKeychainOpen", status)
        }
        self.keychain = opened
        SecKeychainUnlock(opened, UInt32(password.utf8.count), password, true)
        var settings = SecKeychainSettings()
        settings.lockOnSleep = false
        settings.useLockInterval = false
        settings.lockInterval = UInt32.max
        SecKeychainSetSettings(opened, &settings)
    }

    /// Deletes the on-disk keychain file. Best-effort, called on every code path (including
    /// failures) so the spike never leaves keychain litter -- and never touches the user's
    /// login keychain, which this type intentionally never references.
    func cleanup() {
        if let kc = keychain {
            SecKeychainDelete(kc)
            keychain = nil
        }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// Releases this handle without deleting the on-disk file -- used when a second process
    /// invocation reopened a keychain that the *original* creating process still owns and will
    /// delete once its own paired experiment finishes.
    func disown() {
        keychain = nil
    }
}

/// Generates a P-256 key pair and assembles a `SecIdentity` for it.
///
/// - Parameter secureEnclave: when true, the private key is generated with
///   `kSecAttrTokenIDSecureEnclave` (non-extractable, lives in the SEP); when false, an
///   ordinary software P-256 key is generated the same way, through the same code path, so the
///   only variable between the two runs is the token backing.
/// - Parameter persistent: informational only (recorded in findings) -- the private key item
///   is always added with `kSecAttrIsPermanent: true` because assembling a `SecIdentity` needs
///   a private key + certificate that are both actually present in a keychain. Whether the item
///   is still there after process relaunch is what `relaunch-check` tests; call
///   `cleanupIdentity`/`TemporaryKeychain.cleanup()` when done regardless.
/// - Parameter dataProtectionKeychain: true routes through the modern, per-app "data protection
///   keychain" (`kSecUseDataProtectionKeychain`) -- never the login keychain. false routes
///   through `temporaryKeychain`, which MUST be supplied and MUST NOT be the login keychain;
///   this spike never writes keychain items outside one of these two throwaway stores.
func generateIdentity(
    label: String,
    secureEnclave: Bool,
    persistent: Bool,
    dataProtectionKeychain: Bool = true,
    temporaryKeychain: TemporaryKeychain? = nil
) throws -> GeneratedIdentity {
    precondition(dataProtectionKeychain || temporaryKeychain != nil, "legacy mode requires a TemporaryKeychain -- never the login keychain")
    var privateKeyAttrs: [CFString: Any] = [
        kSecAttrIsPermanent: true,
        kSecAttrLabel: label,
        kSecAttrApplicationTag: Data(label.utf8)
    ]

    var accessControl: SecAccessControl?
    if secureEnclave {
        var acError: Unmanaged<CFError>?
        accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [],
            &acError
        )
        if let acError { throw IdentityError.keyGenerationFailed(errSecParam, acError.takeRetainedValue()) }
        privateKeyAttrs[kSecAttrAccessControl] = accessControl
    } else {
        privateKeyAttrs[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }

    var attrs: [CFString: Any] = [
        kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits: 256,
        kSecPrivateKeyAttrs: privateKeyAttrs
    ]
    if dataProtectionKeychain {
        attrs[kSecUseDataProtectionKeychain] = true
    } else if let kc = temporaryKeychain?.keychain {
        attrs[kSecUseKeychain] = kc
    }
    if secureEnclave {
        attrs[kSecAttrTokenID] = kSecAttrTokenIDSecureEnclave
    }

    var cfError: Unmanaged<CFError>?
    guard let privateKey = SecKeyCreateRandomKey(attrs as CFDictionary, &cfError) else {
        let err = cfError?.takeRetainedValue()
        let status = (err.map { CFErrorGetCode($0) }).map { OSStatus($0) } ?? errSecParam
        throw IdentityError.keyGenerationFailed(status, err)
    }

    guard let publicKey = SecKeyCopyPublicKey(privateKey) else { throw IdentityError.noPublicKey }
    var exportError: Unmanaged<CFError>?
    guard let rawPublicKeyData = SecKeyCopyExternalRepresentation(publicKey, &exportError) as Data? else {
        throw IdentityError.publicKeyExportFailed(exportError?.takeRetainedValue())
    }
    let rawPoint = [UInt8](rawPublicKeyData)

    let certData = try buildSelfSignedP256Certificate(
        commonName: label,
        publicKeyRawPoint: rawPoint,
        serial: Int.random(in: 1...Int(Int32.max)),
        notBefore: Date().addingTimeInterval(-3600),
        notAfter: Date().addingTimeInterval(2 * 24 * 3600)
    ) { tbs in
        var signError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey, .ecdsaSignatureMessageX962SHA256, Data(tbs) as CFData, &signError
        ) as Data? else {
            throw IdentityError.signingFailed(signError?.takeRetainedValue())
        }
        return [UInt8](signature)
    }

    guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
        throw IdentityError.certificateCreationFailed
    }

    // Remove any stale item with the same label from a previous (crashed/interrupted) run
    // before adding -- SecItemAdd fails with errSecDuplicateItem otherwise.
    var deleteQuery: [CFString: Any] = [
        kSecClass: kSecClassCertificate,
        kSecAttrLabel: label
    ]
    var addQuery: [CFString: Any] = [
        kSecClass: kSecClassCertificate,
        kSecValueRef: certificate,
        kSecAttrLabel: label
    ]
    var identityQuery: [CFString: Any] = [
        kSecClass: kSecClassIdentity,
        kSecAttrLabel: label,
        kSecReturnRef: true
    ]
    if dataProtectionKeychain {
        deleteQuery[kSecUseDataProtectionKeychain] = true
        addQuery[kSecUseDataProtectionKeychain] = true
        identityQuery[kSecUseDataProtectionKeychain] = true
    } else if let kc = temporaryKeychain?.keychain {
        deleteQuery[kSecMatchSearchList] = [kc]
        addQuery[kSecUseKeychain] = kc
        identityQuery[kSecMatchSearchList] = [kc]
    }
    SecItemDelete(deleteQuery as CFDictionary)

    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
        throw IdentityError.keychainAddFailed("certificate", addStatus)
    }

    var result: CFTypeRef?
    let status = SecItemCopyMatching(identityQuery as CFDictionary, &result)
    guard status == errSecSuccess, let ref = result else {
        throw IdentityError.identityLookupFailed(status)
    }
    // swiftlint:disable:next force_cast
    let secIdentity = (ref as! SecIdentity)

    return GeneratedIdentity(
        label: label,
        backing: secureEnclave ? .secureEnclave : .software,
        privateKey: privateKey,
        certificate: certificate,
        secIdentity: secIdentity,
        spkiSha256: spkiSha256(rawPoint: rawPoint)
    )
}

/// Loads a previously generated, persistent identity back from the data protection keychain by
/// label -- used to test whether an SE key survives process relaunch without regenerating it.
func loadPersistentIdentity(label: String) throws -> GeneratedIdentity? {
    let keyQuery: [CFString: Any] = [
        kSecClass: kSecClassKey,
        kSecAttrLabel: label,
        kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        kSecUseDataProtectionKeychain: true,
        kSecReturnRef: true
    ]
    var keyResult: CFTypeRef?
    let keyStatus = SecItemCopyMatching(keyQuery as CFDictionary, &keyResult)
    guard keyStatus == errSecSuccess, let keyRef = keyResult else { return nil }
    // swiftlint:disable:next force_cast
    let privateKey = (keyRef as! SecKey)

    let identityQuery: [CFString: Any] = [
        kSecClass: kSecClassIdentity,
        kSecAttrLabel: label,
        kSecUseDataProtectionKeychain: true,
        kSecReturnRef: true
    ]
    var identityResult: CFTypeRef?
    let identityStatus = SecItemCopyMatching(identityQuery as CFDictionary, &identityResult)
    guard identityStatus == errSecSuccess, let identityRef = identityResult else {
        throw IdentityError.identityLookupFailed(identityStatus)
    }
    // swiftlint:disable:next force_cast
    let secIdentity = (identityRef as! SecIdentity)

    var certRef: SecCertificate?
    SecIdentityCopyCertificate(secIdentity, &certRef)
    guard let certificate = certRef else { throw IdentityError.certificateCreationFailed }

    guard let publicKey = SecKeyCopyPublicKey(privateKey) else { throw IdentityError.noPublicKey }
    var exportError: Unmanaged<CFError>?
    guard let rawPublicKeyData = SecKeyCopyExternalRepresentation(publicKey, &exportError) as Data? else {
        throw IdentityError.publicKeyExportFailed(exportError?.takeRetainedValue())
    }

    let attrsQuery: [CFString: Any] = [
        kSecClass: kSecClassKey,
        kSecAttrLabel: label,
        kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        kSecUseDataProtectionKeychain: true,
        kSecReturnAttributes: true
    ]
    var attrsResult: CFTypeRef?
    SecItemCopyMatching(attrsQuery as CFDictionary, &attrsResult)
    let tokenID = (attrsResult as? [CFString: Any])?[kSecAttrTokenID] as? String
    let backing: KeyBacking = (tokenID == (kSecAttrTokenIDSecureEnclave as String)) ? .secureEnclave : .software

    return GeneratedIdentity(
        label: label,
        backing: backing,
        privateKey: privateKey,
        certificate: certificate,
        secIdentity: secIdentity,
        spkiSha256: spkiSha256(rawPoint: [UInt8](rawPublicKeyData))
    )
}

/// Reopens a previously created `TemporaryKeychain` (by path + password, both supplied by the
/// original `keygen`/`listen` invocation) and looks up the identity by label -- the
/// temporary-keychain equivalent of `loadPersistentIdentity`, used to test relaunch survival
/// without ever touching the login keychain.
func loadPersistentIdentity(fromTemporaryKeychainAt directory: URL, password: String, label: String) throws -> (GeneratedIdentity, TemporaryKeychain)? {
    let kc = try TemporaryKeychain(directory: directory, password: password, create: false)
    guard let keychain = kc.keychain else { return nil }

    let identityQuery: [CFString: Any] = [
        kSecClass: kSecClassIdentity,
        kSecAttrLabel: label,
        kSecMatchSearchList: [keychain],
        kSecReturnRef: true
    ]
    var identityResult: CFTypeRef?
    let identityStatus = SecItemCopyMatching(identityQuery as CFDictionary, &identityResult)
    guard identityStatus == errSecSuccess, let identityRef = identityResult else {
        throw IdentityError.identityLookupFailed(identityStatus)
    }
    // swiftlint:disable:next force_cast
    let secIdentity = (identityRef as! SecIdentity)

    var certRef: SecCertificate?
    SecIdentityCopyCertificate(secIdentity, &certRef)
    var privateKeyRef: SecKey?
    SecIdentityCopyPrivateKey(secIdentity, &privateKeyRef)
    guard let certificate = certRef, let privateKey = privateKeyRef else { throw IdentityError.certificateCreationFailed }

    guard let publicKey = SecKeyCopyPublicKey(privateKey) else { throw IdentityError.noPublicKey }
    var exportError: Unmanaged<CFError>?
    guard let rawPublicKeyData = SecKeyCopyExternalRepresentation(publicKey, &exportError) as Data? else {
        throw IdentityError.publicKeyExportFailed(exportError?.takeRetainedValue())
    }

    let identity = GeneratedIdentity(
        label: label,
        backing: .software,
        privateKey: privateKey,
        certificate: certificate,
        secIdentity: secIdentity,
        spkiSha256: spkiSha256(rawPoint: [UInt8](rawPublicKeyData))
    )
    return (identity, kc)
}

/// Attempts to export the private key material -- must fail for a Secure Enclave key
/// (`errSecUnimplemented` / no external representation possible) and is expected to succeed
/// (return non-nil) for a software key. Used to positively confirm non-exportability rather
/// than just asserting it from documentation.
func attemptPrivateKeyExport(_ key: SecKey) -> (data: Data?, error: String?) {
    var error: Unmanaged<CFError>?
    let result = SecKeyCopyExternalRepresentation(key, &error) as Data?
    if let error {
        return (nil, String(describing: error.takeRetainedValue()))
    }
    return (result, nil)
}

/// Deletes the keychain items (private key + certificate) created for `label` from the
/// data-protection keychain. Best-effort, called on every code path including failures so the
/// spike never leaves keychain litter. Deliberately scoped to `kSecUseDataProtectionKeychain`
/// only -- it must NEVER fall back to an unscoped query, which would search (and could delete
/// from) the user's login keychain.
func cleanupIdentity(label: String) {
    let keyQuery: [CFString: Any] = [kSecClass: kSecClassKey, kSecAttrLabel: label, kSecUseDataProtectionKeychain: true]
    let certQuery: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecAttrLabel: label, kSecUseDataProtectionKeychain: true]
    SecItemDelete(keyQuery as CFDictionary)
    SecItemDelete(certQuery as CFDictionary)
}
