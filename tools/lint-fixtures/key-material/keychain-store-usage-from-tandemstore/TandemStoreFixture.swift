import TandemCrypto

// E10-14 fixture (permanent, no add-and-revert): proves the key_material_only_in_crypto
// SwiftLint rule does not fire on code that reaches the Keychain only through the KeychainStore
// protocol (TandemStore's trust store, E13-06, uses exactly this pattern).
struct TandemStoreFixture {
    let keychainStore: any KeychainStore

    func loadIdentityKey(tag: String) throws {
        _ = try keychainStore.copyKey(tag: tag)
    }
}
