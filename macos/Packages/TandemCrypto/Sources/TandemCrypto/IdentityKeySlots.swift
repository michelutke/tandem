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

    /// The tag the pointer names, or -- with the pointer missing or unreadable -- whichever slot
    /// holds a key (primary first), so a lost pointer never orphans a rotated identity.
    public func activeTag() throws -> String {
        do {
            let data = try keychainStore.copyGenericPassword(
                service: Self.pointerService, account: Self.pointerAccount
            )
            if let tag = String(bytes: data, encoding: .utf8),
               tag == identityKeyApplicationTag || tag == Self.secondaryTag {
                return tag
            }
        } catch KeychainError.itemNotFound {
        }
        return try tagHoldingKey()
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

    private func tagHoldingKey() throws -> String {
        for tag in [identityKeyApplicationTag, Self.secondaryTag] {
            do {
                _ = try keychainStore.copyKey(tag: tag)
                return tag
            } catch KeychainError.itemNotFound {
                continue
            }
        }
        return identityKeyApplicationTag
    }
}
