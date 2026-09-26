import CryptoKit
import Foundation

// E10-14 fixture (permanent, no add-and-revert): proves the key_material_only_in_crypto
// SwiftLint rule fires when a package other than TandemCrypto computes HMAC-SHA256 directly.
func hmacFixture(key: SymmetricKey, data: Data) -> Data {
    Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
}
