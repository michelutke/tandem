import Security
import Testing
@testable import TandemCrypto

struct IdentityKeyInaccessibleTests {
    @Test func signingFailure_authFailed_isAuthFailed() {
        #expect(IdentityKeyProvider.signingFailure(forStatus: Int(errSecAuthFailed)) == .authFailed)
    }

    @Test func signingFailure_interactionNotAllowed_isLocked() {
        #expect(IdentityKeyProvider.signingFailure(forStatus: Int(errSecInteractionNotAllowed)) == .locked)
    }

    @Test(arguments: [
        errSecUserCanceled, errSecMissingEntitlement, errSecNoAccessForItem, errSecNotAvailable,
        errSecInteractionRequired, errSecAllocate, errSecIO, errSecDecode, errSecParam
    ])
    func signingFailure_anyOtherStatus_isUnhandledNeverUnusable(status: OSStatus) {
        #expect(IdentityKeyProvider.signingFailure(forStatus: Int(status)) == .unhandled(status: status))
    }
}
