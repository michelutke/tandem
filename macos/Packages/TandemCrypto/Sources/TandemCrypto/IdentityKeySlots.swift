import Foundation

/// The two Keychain application tags the Mac's identity key alternates between (E70-03). The
/// active identity is whichever tag the pointer item names (the fixed `identityKeyApplicationTag`
/// until a rotation completes), and the other tag holds the pending key during a rotation. A
/// rotation switches identity by rewriting that one pointer item -- a Keychain key item cannot be
/// re-tagged -- so the switch is a single atomic write.
public struct IdentityKeySlots: Sendable {
    public static let secondaryTag = "com.tandem.identity.v1.b"

    private static let pointerService = "com.tandem.identity.slot.v1"
    private static let pointerAccount = "active"

    private let keychainStore: any KeychainStore

    public init(keychainStore: any KeychainStore) {
        self.keychainStore = keychainStore
    }

    public func activeTag() throws -> String {
        do {
            let data = try keychainStore.copyGenericPassword(
                service: Self.pointerService, account: Self.pointerAccount
            )
            let tag = String(bytes: data, encoding: .utf8)
            return tag == Self.secondaryTag ? Self.secondaryTag : identityKeyApplicationTag
        } catch KeychainError.itemNotFound {
            return identityKeyApplicationTag
        }
    }

    public func inactiveTag() throws -> String {
        try activeTag() == identityKeyApplicationTag ? Self.secondaryTag : identityKeyApplicationTag
    }

    /// Makes `tag` the active identity key tag.
    public func activate(_ tag: String) throws {
        let data = Data(tag.utf8)
        do {
            try keychainStore.addGenericPassword(
                service: Self.pointerService,
                account: Self.pointerAccount,
                data: data,
                accessibility: .afterFirstUnlockThisDeviceOnly
            )
        } catch KeychainError.duplicateItem {
            try keychainStore.updateGenericPassword(
                service: Self.pointerService, account: Self.pointerAccount, data: data
            )
        }
    }
}
