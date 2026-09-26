import Security

enum SecKeyFixtureError: Error {
    case generationFailed
}

// E10-14 fixture (permanent, no add-and-revert): proves the key_material_only_in_crypto
// SwiftLint rule fires when a package other than TandemCrypto touches SecKey*/SecItem* directly.
func secKeyFixture() throws -> SecKey {
    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits as String: 256
    ]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
        throw SecKeyFixtureError.generationFailed
    }
    return key
}
