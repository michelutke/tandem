import Foundation

/// Minimal DER (Distinguished Encoding Rules) primitives, just enough to hand-build a
/// self-signed X.509 v1 certificate for a P-256 key that may live in the Secure Enclave (whose
/// private key material cannot be exported into a PKCS#12 blob, so the `openssl req -x509`
/// path E03-01 uses for its throwaway identities is not available here).
enum DER {
    static func length(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 {
            bytes.insert(UInt8(v & 0xff), at: 0)
            v >>= 8
        }
        return [UInt8(0x80 | bytes.count)] + bytes
    }

    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + length(content.count) + content
    }

    static func sequence(_ content: [UInt8]) -> [UInt8] { tlv(0x30, content) }
    static func set(_ content: [UInt8]) -> [UInt8] { tlv(0x31, content) }

    static func integer(_ value: Int) -> [UInt8] {
        precondition(value >= 0)
        var v = value
        var bytes: [UInt8] = []
        repeat {
            bytes.insert(UInt8(v & 0xff), at: 0)
            v >>= 8
        } while v > 0
        if bytes[0] >= 0x80 { bytes.insert(0, at: 0) }
        return tlv(0x02, bytes)
    }

    static func oid(_ dotted: String) -> [UInt8] {
        let parts = dotted.split(separator: ".").map { Int($0)! }
        var body: [UInt8] = base128(parts[0] * 40 + parts[1])
        for p in parts.dropFirst(2) { body.append(contentsOf: base128(p)) }
        return tlv(0x06, body)
    }

    private static func base128(_ value: Int) -> [UInt8] {
        var v = value
        var bytes = [UInt8(v & 0x7f)]
        v >>= 7
        while v > 0 {
            bytes.insert(UInt8(v & 0x7f) | 0x80, at: 0)
            v >>= 7
        }
        return bytes
    }

    static func printableString(_ s: String) -> [UInt8] { tlv(0x13, Array(s.utf8)) }

    static func utcTime(_ date: Date) -> [UInt8] {
        let df = DateFormatter()
        df.dateFormat = "yyMMddHHmmss'Z'"
        df.timeZone = TimeZone(identifier: "UTC")
        df.locale = Locale(identifier: "en_US_POSIX")
        return tlv(0x17, Array(df.string(from: date).utf8))
    }

    static func bitString(_ content: [UInt8], unusedBits: UInt8 = 0) -> [UInt8] {
        tlv(0x03, [unusedBits] + content)
    }
}

enum X509OID {
    static let commonName = "2.5.4.3"
    static let ecdsaWithSHA256 = "1.2.840.10045.4.3.2"
    static let ecPublicKey = "1.2.840.10045.2.1"
    static let prime256v1 = "1.2.840.10045.3.1.7"
}

/// Builds a minimal, extension-free, X.509 v1 self-signed certificate DER for a P-256 key.
/// `sign` receives the DER-encoded TBSCertificate bytes and must return an ANSI X9.62
/// DER-encoded ECDSA signature (exactly what `SecKeyCreateSignature` with
/// `.ecdsaSignatureMessageX962SHA256` produces) -- no extra wrapping needed, it drops straight
/// into the certificate's `signatureValue` BIT STRING.
func buildSelfSignedP256Certificate(
    commonName: String,
    publicKeyRawPoint: [UInt8],
    serial: Int,
    notBefore: Date,
    notAfter: Date,
    sign: ([UInt8]) throws -> [UInt8]
) throws -> Data {
    precondition(publicKeyRawPoint.count == 65 && publicKeyRawPoint[0] == 0x04, "expected uncompressed P-256 point")

    let signatureAlgorithm = DER.sequence(DER.oid(X509OID.ecdsaWithSHA256))
    let name = DER.sequence(
        DER.set(
            DER.sequence(DER.oid(X509OID.commonName) + DER.printableString(commonName))
        )
    )
    let validity = DER.sequence(DER.utcTime(notBefore) + DER.utcTime(notAfter))
    let spki = DER.sequence(
        DER.sequence(DER.oid(X509OID.ecPublicKey) + DER.oid(X509OID.prime256v1))
            + DER.bitString(publicKeyRawPoint)
    )

    let tbsCertificate = DER.sequence(
        DER.integer(serial)
            + signatureAlgorithm
            + name
            + validity
            + name
            + spki
    )

    let signature = try sign(tbsCertificate)
    let certificate = DER.sequence(tbsCertificate + signatureAlgorithm + DER.bitString(signature))
    return Data(certificate)
}
