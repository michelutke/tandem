import Foundation
import Security
import SwiftASN1
import X509

/// Fixed Keychain label every identity certificate item is stored under (E10-06, PRD F-1.1).
public let identityCertLabel = "com.tandem.identity.cert.v1"

/// RFC 5280's conventional no-expiry value (E10-06 acceptance): 9999-12-31T23:59:59Z.
private let identityCertNotValidAfter = Date(timeIntervalSince1970: 253_402_300_799)

/// The fixed placeholder subject/issuer every identity certificate carries (E10-06, PRD F-1.1):
/// no host name, user name, account name or serial number -- mirrors the Android
/// `IDENTITY_CERT_SUBJECT` constant (E10-02). SPEC §1 ("Certificate handling and the leaf-only
/// check") never checks this field; only the SPKI pin matters. A function rather than a stored
/// constant because building a `DistinguishedName` throws.
public func identityCertSubject() throws -> DistinguishedName {
    try DistinguishedName {
        CommonName("com.tandem.identity")
    }
}

/// Generates and persists the device's self-signed leaf certificate over the identity key
/// (E10-06, PRD F-1.1, SPEC §1 "Certificate handling and the leaf-only check"). The certificate
/// carries no meaningful identity -- subject and issuer are both the fixed
/// ``identityCertSubject()`` placeholder -- and every field besides its public key and signature
/// is never checked by a peer (only the SPKI pin matters, E10-08). Signing goes through
/// `Certificate.PrivateKey(SecKey)` (`SecKeyCreateSignature` under the hood), so this never
/// extracts the private key -- works whether or not the underlying key is extractable. Reaches
/// the Keychain only through ``KeychainStore`` (E10-16), so unit tests run against
/// `InMemoryKeychainStore`; real Keychain behaviour is covered by hosted `integration:` tests
/// against `SecItemKeychainStore`.
public struct IdentityCertProvider: Sendable {

    private let keychainStore: any KeychainStore
    private let dateProvider: @Sendable () -> Date

    public init(keychainStore: any KeychainStore, dateProvider: @escaping @Sendable () -> Date = Date.init) {
        self.keychainStore = keychainStore
        self.dateProvider = dateProvider
    }

    /// Returns the existing identity certificate over ``IdentityKeyProvider``'s key, or generates
    /// and persists a new self-signed one if none exists yet.
    public func getOrCreateIdentityCertificate() throws -> Certificate {
        let identityKey = try IdentityKeyProvider(keychainStore: keychainStore).getOrCreateIdentityKey()
        do {
            let der = try keychainStore.copyCertificate(label: identityCertLabel)
            return try Certificate(derEncoded: [UInt8](der))
        } catch KeychainError.itemNotFound {
            let certificate = try Self.makeSelfSignedCertificate(identityKey: identityKey, generatedAt: dateProvider())
            try keychainStore.addCertificate(label: identityCertLabel, der: try certificate.derEncodedData())
            return certificate
        }
    }

    private static func makeSelfSignedCertificate(identityKey: SecKey, generatedAt: Date) throws -> Certificate {
        let privateKey = try Certificate.PrivateKey(identityKey)
        let subject = try identityCertSubject()

        return try Certificate(
            version: .v3,
            serialNumber: .randomPositive16Byte(),
            publicKey: privateKey.publicKey,
            notValidBefore: generatedAt.addingTimeInterval(-86_400),
            notValidAfter: identityCertNotValidAfter,
            issuer: subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true))
            },
            issuerPrivateKey: privateKey
        )
    }
}

extension Certificate.SerialNumber {
    /// A random positive 16-byte serial number (E10-06 acceptance). The top bit of the first byte
    /// is cleared before handing the bytes to `Certificate.SerialNumber`, so the value is already
    /// non-negative in DER's two's-complement INTEGER encoding and the encoded length stays
    /// exactly 16 bytes (no extra leading `0x00`). The low bit is set too: a first byte of `0x00` would be
    /// dropped by DER's minimal INTEGER encoding and leave a 15-byte serial (about 1 in 128 certificates).
    fileprivate static func randomPositive16Byte() -> Certificate.SerialNumber {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status)")
        bytes[0] = (bytes[0] & 0x7F) | 0x01
        return Certificate.SerialNumber(bytes: bytes)
    }
}

extension Certificate {
    fileprivate func derEncodedData() throws -> Data {
        var serializer = DER.Serializer()
        try serialize(into: &serializer)
        return Data(serializer.serializedBytes)
    }
}
