import Foundation
import Testing
import TandemCrypto
import X509
@testable import TandemTestSupport

/// E10-06 unit coverage: `IdentityCertProvider` reaches the Keychain only through `KeychainStore`
/// (E10-16), so these run against `InMemoryKeychainStore`. Real Keychain behaviour is covered by
/// hosted `integration:` tests against `SecItemKeychainStore` (E10-07).
@Suite("IdentityCertProvider")
struct IdentityCertProviderTests {

    @Test
    func selfSignedCert_generated_publicKeyEqualsIdentityPublicKey() throws {
        let store = InMemoryKeychainStore()
        let identityKey = try IdentityKeyProvider(keychainStore: store).getOrCreateIdentityKey()

        let certificate = try IdentityCertProvider(keychainStore: store).getOrCreateIdentityCertificate()

        #expect(certificate.publicKey == (try Certificate.PrivateKey(identityKey)).publicKey)
    }

    @Test
    func selfSignedCert_subject_equalsFixedPlaceholderOnly() throws {
        let store = InMemoryKeychainStore()

        let certificate = try IdentityCertProvider(keychainStore: store).getOrCreateIdentityCertificate()

        #expect(try certificate.subject == identityCertSubject())
        #expect(try certificate.issuer == identityCertSubject())
    }

    @Test
    func selfSignedCert_signature_verifiesWithOwnPublicKey() throws {
        let store = InMemoryKeychainStore()

        let certificate = try IdentityCertProvider(keychainStore: store).getOrCreateIdentityCertificate()

        #expect(certificate.publicKey.isValidSignature(certificate.signature, for: certificate))
    }

    @Test
    func selfSignedCert_newProviderSameStore_certAndKeyPublicKeysMatch() throws {
        let store = InMemoryKeychainStore()
        _ = try IdentityCertProvider(keychainStore: store).getOrCreateIdentityCertificate()

        let certificate = try IdentityCertProvider(keychainStore: store).getOrCreateIdentityCertificate()
        let identityKey = try IdentityKeyProvider(keychainStore: store).getOrCreateIdentityKey()

        #expect(certificate.publicKey == (try Certificate.PrivateKey(identityKey)).publicKey)
    }

    @Test
    func selfSignedCert_generated_notAfterIs99991231AndCaFalse() throws {
        let store = InMemoryKeychainStore()

        let certificate = try IdentityCertProvider(keychainStore: store).getOrCreateIdentityCertificate()

        #expect(certificate.notValidAfter == Date(timeIntervalSince1970: 253_402_300_799))
        #expect(try certificate.extensions.basicConstraints == .notCertificateAuthority)
        #expect(try certificate.extensions.keyUsage?.digitalSignature == true)
        #expect(certificate.serialNumber.bytes.count == 16)
    }
}
