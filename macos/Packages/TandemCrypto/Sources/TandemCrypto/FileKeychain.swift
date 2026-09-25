import Foundation
import Security

/// A throwaway, on-disk keychain file -- never the login/default keychain -- for Debug-only test
/// and harness code (E10-07b, D-75). Ported from spike E03-02's `TemporaryKeychain`
/// (docs/spikes/secure-enclave-identity.md): `SecKeychainCreate`/`Open`/`Unlock`/`Delete` are
/// deprecated but fully functional on macOS 26 (gotcha 4); confined to this one file so the
/// deprecation warning doesn't spread. Every query against a `FileKeychain` goes through
/// `KeychainTarget.file`'s per-query `kSecUseKeychain`/`kSecMatchSearchList`, never
/// `SecKeychainSetDefault`/`SecKeychainSetSearchList`, so this never touches the user's login
/// keychain or default search list.
public final class FileKeychain: @unchecked Sendable {

    let keychain: SecKeychain

    private init(keychain: SecKeychain) {
        self.keychain = keychain
    }

    /// Opens the keychain file at `path` if one already exists there, else creates it fresh with
    /// `password`, then unlocks it and disables sleep/interval auto-lock so it stays usable for
    /// the life of the process. Reopening with the same path and password (a second call, in the
    /// same or a later process) unlocks the identical on-disk file -- the file-keychain
    /// equivalent of relaunch persistence (spike E03-02's relaunch experiment).
    public static func createOrOpen(path: String, password: String) throws -> FileKeychain {
        var keychainRef: SecKeychain?
        let status: OSStatus
        if FileManager.default.fileExists(atPath: path) {
            status = SecKeychainOpen(path, &keychainRef)
        } else {
            status = SecKeychainCreate(path, UInt32(password.utf8.count), password, false, nil, &keychainRef)
        }
        guard status == errSecSuccess, let opened = keychainRef else {
            throw KeychainError(status)
        }

        let unlockStatus = SecKeychainUnlock(opened, UInt32(password.utf8.count), password, true)
        guard unlockStatus == errSecSuccess else { throw KeychainError(unlockStatus) }

        var settings = SecKeychainSettings()
        settings.lockOnSleep = false
        settings.useLockInterval = false
        settings.lockInterval = UInt32.max
        SecKeychainSetSettings(opened, &settings)

        return FileKeychain(keychain: opened)
    }

    /// Deletes the on-disk keychain file. Only ever operates on this handle's own `SecKeychain` --
    /// never `SecKeychainSetDefault`/`SecKeychainSetSearchList` -- so it cannot affect the login
    /// keychain or the user's default search list.
    public func delete() {
        SecKeychainDelete(keychain)
    }
}

/// Which keychain a `SecItemKeychainStore` reads and writes (E10-07b, D-75). Production always
/// uses `.dataProtection`; tests and the E15-22 CI harness use `.file` so they never touch the
/// login keychain.
public enum KeychainTarget: Sendable {
    /// The modern, per-app data-protection keychain (`kSecUseDataProtectionKeychain`).
    case dataProtection
    /// A throwaway on-disk keychain file, scoped with `kSecUseKeychain`/`kSecMatchSearchList` --
    /// never the login keychain or default search list.
    case file(FileKeychain)

    /// Attributes for an add (`SecItemAdd`/`SecKeyCreateRandomKey`): `kSecUseKeychain` for a file
    /// target routes the new item straight into that keychain without touching the search list.
    func addAttributes() -> [String: Any] {
        switch self {
        case .dataProtection:
            return [kSecUseDataProtectionKeychain as String: true]
        case .file(let fileKeychain):
            return [kSecUseKeychain as String: fileKeychain.keychain]
        }
    }

    /// Attributes for a search (`SecItemCopyMatching`/`SecItemUpdate`/`SecItemDelete`):
    /// `kSecMatchSearchList` for a file target scopes the query to that keychain only -- it does
    /// not modify the user's actual search list.
    func searchAttributes() -> [String: Any] {
        switch self {
        case .dataProtection:
            return [kSecUseDataProtectionKeychain as String: true]
        case .file(let fileKeychain):
            return [kSecMatchSearchList as String: [fileKeychain.keychain]]
        }
    }
}
