import Foundation
import Security

/// A throwaway P-256 self-signed identity plus the SecIdentity handle Network.framework needs.
/// Backed by a temporary, on-disk keychain (never the login keychain) that the caller must
/// delete via `TemporaryKeychain.cleanup()`.
struct GeneratedIdentity {
    let label: String
    let secIdentity: SecIdentity
    let certificate: SecCertificate
}

enum IdentityError: Error, CustomStringConvertible {
    case importFailed(OSStatus)
    case noIdentityInImport
    case noCertificate

    var description: String {
        switch self {
        case .importFailed(let status): return "SecPKCS12Import failed: \(status)"
        case .noIdentityInImport: return "SecPKCS12Import returned no identity"
        case .noCertificate: return "SecIdentityCopyCertificate failed"
        }
    }
}

/// Manages one temporary macOS keychain file on disk for the lifetime of a spike run.
/// Gotcha: `SecKeychainCreate` is deprecated (no fully modern replacement for an ephemeral,
/// ACL-free identity store), but it is still functional on macOS 26 and is exactly the "use a
/// temporary keychain" pattern the task calls for -- it never touches the login keychain.
final class TemporaryKeychain {
    let url: URL
    private var keychain: SecKeychain?
    private let password = UUID().uuidString

    init() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nwlistener-spike-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("spike.keychain-db")

        var kc: SecKeychain?
        let status = SecKeychainCreate(url.path, UInt32(password.utf8.count), password, false, nil, &kc)
        guard status == errSecSuccess, let created = kc else {
            throw IdentityError.importFailed(status)
        }
        self.keychain = created

        // Keep the keychain unlocked for the lifetime of the process; this is a throwaway
        // spike identity store, not a user-facing secret.
        SecKeychainUnlock(created, UInt32(password.utf8.count), password, true)
        var settings = SecKeychainSettings()
        settings.lockOnSleep = false
        settings.useLockInterval = false
        settings.lockInterval = UInt32.max
        SecKeychainSetSettings(created, &settings)
    }

    func importPKCS12(data: Data, passphrase: String) throws -> GeneratedIdentity {
        guard let kc = keychain else { throw IdentityError.importFailed(errSecInvalidKeychain) }
        let options: [CFString: Any] = [
            kSecImportExportPassphrase: passphrase,
            kSecImportExportKeychain: kc
        ]
        var rawItems: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &rawItems)
        guard status == errSecSuccess, let items = rawItems as? [[CFString: Any]], let first = items.first else {
            throw IdentityError.importFailed(status)
        }
        guard let identity = first[kSecImportItemIdentity] else {
            throw IdentityError.noIdentityInImport
        }
        // swiftlint:disable:next force_cast
        let secIdentity = identity as! SecIdentity
        var certRef: SecCertificate?
        let certStatus = SecIdentityCopyCertificate(secIdentity, &certRef)
        guard certStatus == errSecSuccess, let cert = certRef else {
            throw IdentityError.noCertificate
        }
        let label = (first[kSecImportItemLabel] as? String) ?? "unlabeled"
        return GeneratedIdentity(label: label, secIdentity: secIdentity, certificate: cert)
    }

    /// Deletes the on-disk keychain file. Best-effort; spikes run short-lived so a leaked temp
    /// file in TMPDIR is low-risk, but we still clean up.
    func cleanup() {
        if let kc = keychain {
            SecKeychainDelete(kc)
        }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

/// Shells out to openssl to generate a P-256 key + self-signed cert, then packages it as a
/// PKCS#12 blob in memory (never written unencrypted to disk longer than the temp dir's
/// lifetime, and the temp dir is removed immediately after import).
func generateSelfSignedP256Identity(commonName: String, workDir: URL) throws -> (pkcs12: Data, passphrase: String) {
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    let keyPath = workDir.appendingPathComponent("\(commonName).key.pem")
    let certPath = workDir.appendingPathComponent("\(commonName).cert.pem")
    let p12Path = workDir.appendingPathComponent("\(commonName).p12")
    defer {
        try? FileManager.default.removeItem(at: keyPath)
        try? FileManager.default.removeItem(at: certPath)
        try? FileManager.default.removeItem(at: p12Path)
    }

    _ = try runOpenSSL(["ecparam", "-genkey", "-name", "prime256v1", "-noout", "-out", keyPath.path])
    _ = try runOpenSSL([
        "req", "-new", "-x509", "-key", keyPath.path, "-out", certPath.path,
        "-days", "2", "-subj", "/CN=\(commonName)", "-sha256"
    ])

    let passphrase = UUID().uuidString
    // Gotcha (documented in findings): OpenSSL 3's default PKCS12 export uses PBES2/AES-256 +
    // SHA-256 MAC, which older Security.framework PKCS12 parsing code historically rejected.
    // `-legacy` forces RC2/3DES so `SecPKCS12Import` reliably accepts the blob; both modes are
    // exercised by Scripts/run-experiments.sh and the result is recorded in the findings doc.
    _ = try runOpenSSL([
        "pkcs12", "-export", "-legacy",
        "-inkey", keyPath.path, "-in", certPath.path,
        "-out", p12Path.path, "-passout", "pass:\(passphrase)"
    ])
    let data = try Data(contentsOf: p12Path)
    return (data, passphrase)
}
