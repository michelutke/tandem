import Foundation
import Security
import CryptoKit
import Darwin

enum PinError: Error, CustomStringConvertible {
    case noPublicKey
    case unexpectedKeyRepresentation(count: Int, firstByte: UInt8?)

    var description: String {
        switch self {
        case .noPublicKey: return "SecCertificateCopyKey returned nil"
        case .unexpectedKeyRepresentation(let count, let first):
            return "expected 65-byte uncompressed P-256 point (0x04 || X || Y), got \(count) bytes, first=\(String(describing: first))"
        }
    }
}

/// Fixed ASN.1 DER prefix for a SubjectPublicKeyInfo wrapping an uncompressed P-256
/// (secp256r1 / prime256v1, OID 1.2.840.10045.3.1.7) EC public key under id-ecPublicKey
/// (OID 1.2.840.10045.2.1). Concatenated with the 65-byte raw point (0x04 || X(32) || Y(32))
/// this reproduces the exact 91-byte SPKI DER that E01-01 / D-19 pin against -- see
/// docs/spikes/nwlistener-mtls.md for the byte-count derivation.
private let p256SPKIPrefix: [UInt8] = [
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
    0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00
]

func spkiDER(for certificate: SecCertificate) throws -> Data {
    guard let key = SecCertificateCopyKey(certificate) else { throw PinError.noPublicKey }
    var error: Unmanaged<CFError>?
    guard let raw = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
        throw error!.takeRetainedValue() as Error
    }
    guard raw.count == 65, raw.first == 0x04 else {
        throw PinError.unexpectedKeyRepresentation(count: raw.count, firstByte: raw.first)
    }
    return Data(p256SPKIPrefix) + raw
}

func spkiFingerprint(for certificate: SecCertificate) throws -> Data {
    Data(SHA256.hash(data: try spkiDER(for: certificate)))
}

/// Constant-time compare per D-19 / E01-01 ("compare (constant time) against the trust store").
func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
    guard a.count == b.count else { return false }
    return a.withUnsafeBytes { ab in
        b.withUnsafeBytes { bb in
            timingsafe_bcmp(ab.baseAddress, bb.baseAddress, a.count) == 0
        }
    }
}

func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

func dataFromHex(_ hexString: String) -> Data? {
    let trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count % 2 == 0 else { return nil }
    var data = Data(capacity: trimmed.count / 2)
    var index = trimmed.startIndex
    while index < trimmed.endIndex {
        let next = trimmed.index(index, offsetBy: 2)
        guard let byte = UInt8(trimmed[index..<next], radix: 16) else { return nil }
        data.append(byte)
        index = next
    }
    return data
}
