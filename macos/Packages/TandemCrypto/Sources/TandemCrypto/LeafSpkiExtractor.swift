import Foundation
import SwiftASN1

/// Extracts a leaf certificate's `SubjectPublicKeyInfo` DER exactly as it appears in the
/// certificate's own encoding (SPEC.md §1 "Certificate handling and the leaf-only check",
/// invariant 6, D-19) -- never reconstructed from a decoded key's canonical representation, which
/// would silently normalize away a compressed point or explicit EC parameters instead of letting
/// ``SpkiFingerprint/of(spkiDer:)`` see, and reject, them. This walks the certificate's own ASN.1
/// structure by hand with SwiftASN1's low-level node API rather than `X509.Certificate.PublicKey`:
/// that type re-derives its `subjectPublicKeyInfoBytes` from a parsed CryptoKit key, which is
/// always canonical/uncompressed on the way back out regardless of how the key was originally
/// encoded on the wire.
///
/// ```
/// Certificate      ::= SEQUENCE { tbsCertificate TBSCertificate, ... }
/// TBSCertificate   ::= SEQUENCE { version [0] EXPLICIT Version DEFAULT v1, serialNumber,
///                                 signature, issuer, validity, subject,
///                                 subjectPublicKeyInfo SubjectPublicKeyInfo, ... }
/// ```
public enum LeafSpkiExtractor {
    public enum ExtractionError: Error, Equatable {
        case malformedCertificate
    }

    /// `certificateDER` is a leaf certificate's own DER encoding (e.g. `SecCertificateCopyData`).
    /// Returns the exact bytes of its `SubjectPublicKeyInfo` field, untouched -- ready to hand to
    /// ``SpkiFingerprint/of(spkiDer:)`` for validation and hashing.
    public static func subjectPublicKeyInfoDER(certificateDER: Data) throws -> Data {
        guard let field = try? locateSubjectPublicKeyInfo(in: certificateDER) else {
            throw ExtractionError.malformedCertificate
        }
        return Data(field.encodedBytes)
    }

    /// The optional `[0] EXPLICIT Version` field is the only `TBSCertificate` field encoded with a
    /// context-specific tag; every other field here is universal, so its presence is unambiguous.
    private static let explicitVersionTag = ASN1Identifier(tagWithNumber: 0, tagClass: .contextSpecific)

    private static func locateSubjectPublicKeyInfo(in certificateDER: Data) throws -> ASN1Node {
        let certificate = try DER.parse([UInt8](certificateDER))
        guard case .constructed(let certificateFields) = certificate.content else {
            throw ExtractionError.malformedCertificate
        }

        var certificateIterator = certificateFields.makeIterator()
        guard
            let tbsCertificate = certificateIterator.next(),
            case .constructed(let tbsFields) = tbsCertificate.content
        else {
            throw ExtractionError.malformedCertificate
        }

        var tbsIterator = tbsFields.makeIterator()
        guard var field = tbsIterator.next() else {
            throw ExtractionError.malformedCertificate
        }

        if field.identifier == explicitVersionTag {
            guard let serialNumber = tbsIterator.next() else {
                throw ExtractionError.malformedCertificate
            }
            field = serialNumber
        }

        // `field` is now `serialNumber`; skip it, `signature`, `issuer`, `validity`, and `subject`
        // in turn to land on `subjectPublicKeyInfo`.
        for _ in 0..<5 {
            guard let next = tbsIterator.next() else {
                throw ExtractionError.malformedCertificate
            }
            field = next
        }

        guard field.identifier == .sequence else {
            throw ExtractionError.malformedCertificate
        }
        return field
    }
}
