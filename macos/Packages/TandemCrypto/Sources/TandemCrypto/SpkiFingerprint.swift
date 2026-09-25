import CryptoKit
import Foundation

/// SPKI SHA-256 fingerprint computation (E10-08, SPEC.md #1 "Certificate handling and the
/// leaf-only check" / "Verify-callback algorithm"): trust is bound to the leaf certificate's
/// SubjectPublicKeyInfo, never to IP addresses or device IDs (invariant 3). The leaf's public key
/// MUST be an uncompressed P-256 SubjectPublicKeyInfo, exactly `expectedSpkiDerByteCount` bytes of
/// DER; anything else is rejected before any fingerprint is computed or compared.
///
/// The DER is parsed by hand (no swift-certificates/SwiftASN1 dependency yet -- E10-06 introduces
/// that dependency on its own branch) with a small, strict TLV reader that never reads past the
/// end of the buffer and rejects non-minimal length encodings.
public enum SpkiFingerprint {
    public enum ValidationError: Error, Equatable {
        case unsupportedPointEncoding
        case unsupportedKeyType
        case malformedSpki
    }

    /// A valid uncompressed P-256 SPKI DER is always exactly this many bytes: 2-byte outer
    /// SEQUENCE header + 2-byte AlgorithmIdentifier SEQUENCE header + 2-byte + 7-byte
    /// `ecPublicKey` OID + 2-byte + 8-byte `prime256v1` OID + 3-byte BIT STRING header (tag,
    /// length, unused-bits count) + 65-byte uncompressed point.
    public static let expectedSpkiDerByteCount = 91

    /// Validates `spkiDer` is an uncompressed P-256 SubjectPublicKeyInfo DER of exactly
    /// `expectedSpkiDerByteCount` bytes, then returns the 32-byte SHA-256 digest over it.
    /// Throws `ValidationError` before hashing anything that fails validation.
    public static func compute(spkiDer: Data) throws -> Data {
        try validate(spkiDer: spkiDer)
        return Data(SHA256.hash(data: spkiDer))
    }

    /// `compute(spkiDer:)`'s digest, base64url-encoded without padding (43 chars for 32 bytes) --
    /// same format as the QR payload's `fp` field.
    public static func computeBase64URLString(spkiDer: Data) throws -> String {
        base64URLString(for: try compute(spkiDer: spkiDer))
    }

    public static func base64URLString(for fingerprint: Data) -> String {
        fingerprint.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 1.2.840.10045.2.1 (`ecPublicKey`), DER content bytes.
    private static let ecPublicKeyOID: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]
    /// 1.2.840.10045.3.1.7 (`prime256v1`), DER content bytes.
    private static let prime256v1OID: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]

    private static let sequenceTag: UInt8 = 0x30
    private static let oidTag: UInt8 = 0x06
    private static let bitStringTag: UInt8 = 0x03

    private static func validate(spkiDer: Data) throws {
        var outerReader = DERReader(spkiDer)
        let outer = try outerReader.readTLV()
        guard outer.tag == sequenceTag, outerReader.isAtEnd else {
            throw ValidationError.malformedSpki
        }

        var spkiReader = DERReader(outer.content)
        let algorithmIdentifier = try spkiReader.readTLV()
        guard algorithmIdentifier.tag == sequenceTag else {
            throw ValidationError.malformedSpki
        }
        try validateAlgorithmIdentifier(algorithmIdentifier.content)

        let subjectPublicKey = try spkiReader.readTLV()
        let point = try validateBitString(subjectPublicKey)
        try validatePoint(point)
    }

    private static func validateAlgorithmIdentifier(_ content: Data) throws {
        var reader = DERReader(content)

        let keyType = try reader.readTLV()
        guard keyType.tag == oidTag else {
            throw ValidationError.malformedSpki
        }
        guard [UInt8](keyType.content) == ecPublicKeyOID else {
            throw ValidationError.unsupportedKeyType
        }

        let curve = try reader.readTLV()
        guard curve.tag == oidTag else {
            throw ValidationError.malformedSpki
        }
        guard [UInt8](curve.content) == prime256v1OID else {
            throw ValidationError.unsupportedKeyType
        }
    }

    private static func validateBitString(_ tlv: DERTLV) throws -> Data {
        guard tlv.tag == bitStringTag, let unusedBitsCount = tlv.content.first, unusedBitsCount == 0x00 else {
            throw ValidationError.malformedSpki
        }
        return tlv.content.dropFirst()
    }

    private static func validatePoint(_ point: Data) throws {
        guard let prefix = point.first else {
            throw ValidationError.malformedSpki
        }
        guard prefix == 0x04 else {
            throw ValidationError.unsupportedPointEncoding
        }
        guard point.count - 1 == 64 else {
            throw ValidationError.malformedSpki
        }
    }
}

/// One decoded DER tag-length-value: the tag byte and its content bytes (length already consumed
/// and validated by `DERReader`).
private struct DERTLV {
    let tag: UInt8
    let content: Data
}

/// Minimal, strict DER TLV reader: reads a tag, a length (short form for values < 0x80, long form
/// otherwise, rejecting non-minimal encodings), then that many content bytes. Never reads past
/// the end of `bytes`; any bounds violation or malformed length throws `.malformedSpki`.
private struct DERReader {
    private let bytes: [UInt8]
    private var offset: Int

    init(_ data: Data) {
        bytes = [UInt8](data)
        offset = 0
    }

    var isAtEnd: Bool { offset == bytes.count }

    mutating func readTLV() throws -> DERTLV {
        guard offset < bytes.count else {
            throw SpkiFingerprint.ValidationError.malformedSpki
        }
        let tag = bytes[offset]
        offset += 1

        let length = try readLength()
        guard offset + length <= bytes.count else {
            throw SpkiFingerprint.ValidationError.malformedSpki
        }
        let content = Data(bytes[offset..<offset + length])
        offset += length
        return DERTLV(tag: tag, content: content)
    }

    private mutating func readLength() throws -> Int {
        guard offset < bytes.count else {
            throw SpkiFingerprint.ValidationError.malformedSpki
        }
        let first = bytes[offset]
        offset += 1

        if first & 0x80 == 0 {
            return Int(first)
        }

        let lengthByteCount = Int(first & 0x7F)
        guard lengthByteCount > 0, lengthByteCount <= 4 else {
            throw SpkiFingerprint.ValidationError.malformedSpki
        }
        guard offset + lengthByteCount <= bytes.count else {
            throw SpkiFingerprint.ValidationError.malformedSpki
        }
        guard bytes[offset] != 0 else {
            throw SpkiFingerprint.ValidationError.malformedSpki
        }

        var value = 0
        for index in 0..<lengthByteCount {
            value = (value << 8) | Int(bytes[offset + index])
        }
        offset += lengthByteCount

        guard value >= 0x80 else {
            throw SpkiFingerprint.ValidationError.malformedSpki
        }
        return value
    }
}
