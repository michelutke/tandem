import Foundation
import Security
import TandemCrypto

/// A throwaway on-disk keychain for the hosted tests in this target (E10-07b, D-75): a fresh
/// directory under `FileManager.default.temporaryDirectory`, a random per-instance password, and
/// a `SecItemKeychainStore` already pointed at it via `KeychainTarget.file`. Never the login
/// keychain. Unlike `TandemCryptoTests`' own `TemporaryKeychain`, this target has no
/// `@testable import TandemCrypto` access, so it is built entirely from `TandemCrypto`'s public
/// API. Callers must call `cleanup()` (ideally in `defer`) to delete the keychain file and its
/// directory.
final class TemporaryKeychain: @unchecked Sendable {

    let store: SecItemKeychainStore

    private let directory: URL
    private let fileKeychain: FileKeychain

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tandem-transport-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("test.keychain-db").path
        let password = UUID().uuidString

        self.directory = directory
        self.fileKeychain = try FileKeychain.createOrOpen(path: path, password: password)
        self.store = SecItemKeychainStore(target: .file(fileKeychain))
    }

    /// Deletes the on-disk keychain file and its containing directory. `FileKeychain.delete()`
    /// only ever operates on this instance's own keychain, so this never touches the login
    /// keychain.
    func cleanup() {
        fileKeychain.delete()
        try? FileManager.default.removeItem(at: directory)
    }

    func makeSecIdentity() throws -> SecIdentity {
        try SecIdentityProvider(keychainStore: store).getOrCreateSecIdentity()
    }
}
