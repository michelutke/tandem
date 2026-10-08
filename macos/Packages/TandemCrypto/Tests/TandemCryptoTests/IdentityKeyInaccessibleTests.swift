import Security
import Testing
@testable import TandemCrypto

struct IdentityKeyInaccessibleTests {
    @Test func inaccessibleKeyError_authFailed_isAuthFailed() {
        #expect(IdentityKeyProvider.inaccessibleKeyError(forStatus: Int(errSecAuthFailed)) == .authFailed)
    }

    @Test func inaccessibleKeyError_interactionNotAllowed_isLocked() {
        #expect(IdentityKeyProvider.inaccessibleKeyError(forStatus: Int(errSecInteractionNotAllowed)) == .locked)
    }

    @Test func inaccessibleKeyError_userCanceled_isUnhandledStatus() {
        #expect(
            IdentityKeyProvider.inaccessibleKeyError(forStatus: Int(errSecUserCanceled))
                == .unhandled(status: errSecUserCanceled)
        )
    }

    @Test func inaccessibleKeyError_otherStatus_isNil() {
        #expect(IdentityKeyProvider.inaccessibleKeyError(forStatus: Int(errSecParam)) == nil)
    }
}
