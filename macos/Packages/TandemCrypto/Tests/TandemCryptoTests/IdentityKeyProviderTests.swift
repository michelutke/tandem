import Foundation
import Security
import Testing
@testable import TandemCrypto

@Suite("IdentityKeyProvider key attributes")
struct IdentityKeyProviderAttributesTests {

    @Test
    func getOrCreateIdentityKey_addRequest_usesDataProtectionKeychainOwnGroup() {
        let attributes = SecItemKeychainStore.keyAttributes(
            tag: identityKeyApplicationTag,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )

        #expect(attributes[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(attributes[kSecAttrAccessGroup as String] == nil)
    }
}
