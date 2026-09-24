import Foundation
import Testing
import TandemCrypto
@testable import TandemTestSupport

@Suite("InMemoryKeychainStore")
struct InMemoryKeychainStoreTests {

    @Test
    func inMemoryKeychain_addThenCopy_returnsSameData() throws {
        let store = InMemoryKeychainStore()
        let data = Data("secret".utf8)

        try store.addGenericPassword(
            service: "com.tandem.test",
            account: "account",
            data: data,
            accessibility: .afterFirstUnlockThisDeviceOnly
        )

        #expect(try store.copyGenericPassword(service: "com.tandem.test", account: "account") == data)
    }

    @Test
    func inMemoryKeychain_addWithAccessibility_recordsAfterFirstUnlockThisDeviceOnly() throws {
        let store = InMemoryKeychainStore()

        try store.addGenericPassword(
            service: "com.tandem.test",
            account: "account",
            data: Data(),
            accessibility: .afterFirstUnlockThisDeviceOnly
        )

        #expect(
            store.recordedAccessibility(service: "com.tandem.test", account: "account")
                == .afterFirstUnlockThisDeviceOnly
        )
    }

    @Test
    func inMemoryKeychain_injectedInteractionNotAllowed_throwsKeychainErrorLocked() {
        let store = InMemoryKeychainStore()
        store.failNextOperation(with: .locked)

        #expect(throws: KeychainError.locked) {
            try store.copyGenericPassword(service: "com.tandem.test", account: "account")
        }
    }
}
