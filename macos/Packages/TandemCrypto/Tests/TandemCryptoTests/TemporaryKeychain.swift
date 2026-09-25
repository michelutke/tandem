import Foundation
@testable import TandemCrypto

/// A throwaway on-disk keychain for the hosted tests in this target (E10-07b, D-75): a fresh
/// directory under `FileManager.default.temporaryDirectory`, a random per-instance password, and
/// a `SecItemKeychainStore` already pointed at it via `KeychainTarget.file`. Never the login
/// keychain -- ported from spike E03-02's `TemporaryKeychain`
/// (docs/spikes/secure-enclave-identity.md). This lives in `Tests/` rather than
/// `TandemTestSupport` (unlike `InMemoryKeychainStore`): `TandemTestSupport` already depends on
/// `TandemCrypto`, so a shared product here would be a package dependency cycle. Callers must
/// call `cleanup()` (ideally in `defer`) to delete the keychain file and its directory.
final class TemporaryKeychain: @unchecked Sendable {

    let store: SecItemKeychainStore
    let path: String
    let password: String

    private let directory: URL
    private let fileKeychain: FileKeychain

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tandem-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("test.keychain-db").path
        let password = UUID().uuidString

        self.directory = directory
        self.path = path
        self.password = password
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
}
