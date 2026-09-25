import Foundation
import TandemCrypto

/// Constructs the `KeychainStore` TandemApp bootstraps its identity from (E10-07b, D-75).
/// Release always uses the data-protection keychain. A Debug build may instead point at a
/// throwaway on-disk file keychain via the `-HarnessKeychainPath <path>` launch argument (read
/// through `UserDefaults`, matching Apple's `-key value` launch-argument auto-registration) with
/// the password passed as the `TANDEM_HARNESS_KEYCHAIN_PASSWORD` *environment* variable rather
/// than another launch argument, so it never appears in `ps` output -- this is how the E15-22 CI
/// harness runs Tandem.app against a dedicated keychain instead of the data-protection keychain.
/// No silent fallback: a Debug run that omits `-HarnessKeychainPath` still uses the
/// data-protection keychain like Release does, and whatever `SecIdentityProvider` throws over it
/// (e.g. `-34018` on an unsigned build with no `keychain-access-groups` entitlement) is left to
/// surface as a visible error, never swallowed.
enum KeychainStoreFactory {
    static func make() -> any KeychainStore {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "HarnessKeychainPath") {
            guard let password = ProcessInfo.processInfo.environment["TANDEM_HARNESS_KEYCHAIN_PASSWORD"] else {
                fatalError("-HarnessKeychainPath set without TANDEM_HARNESS_KEYCHAIN_PASSWORD")
            }
            do {
                let fileKeychain = try FileKeychain.createOrOpen(path: path, password: password)
                return SecItemKeychainStore(target: .file(fileKeychain))
            } catch {
                fatalError("failed to open harness keychain at \(path): \(error)")
            }
        }
        #endif
        return SecItemKeychainStore(target: .dataProtection)
    }
}
