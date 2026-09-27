#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// The Bonjour instance-name rotating id (E21-02, SPEC.md "Discovery TXT record"): a value that
/// changes once per UTC calendar day so the advertised `_tandem._tcp` service name never sits
/// still on the local network, without either peer needing to exchange anything beyond the
/// already-pinned mac SPKI fingerprint.
///
/// `dayIndex = floor(unixSecondsUtc / 86400)`, computed from UTC seconds only -- never
/// `Calendar`/`TimeZone`, since a device in any local time zone must derive the same day boundary.
/// `id = first 8 bytes of HMAC-SHA256(key: macSpkiFingerprint, message: dayIndex as unsigned
/// 64-bit big-endian)`. A receiver that has this Mac's paired SPKI fingerprint recomputes the id
/// for `dayIndex-1`/`dayIndex`/`dayIndex+1` (a +/-1 day clock-skew window) and recognizes the
/// advertised id only if it matches one of those three candidates byte-for-byte as a
/// case-sensitive string -- ``recognize(advertisedIdHex:candidateHexIds:)`` never decodes back to
/// bytes before comparing, so an uppercase-hex re-encoding of an otherwise-correct id is not
/// recognized.
public enum DiscoveryRotatingId {
    public enum RecognitionError: Error, Equatable {
        case notRecognized
    }

    private static let secondsPerDay: Int64 = 86_400
    private static let idByteCount = 8

    /// Floors `unixSecondsUtc / 86400` correctly for negative inputs too (a receiver computes
    /// `dayIndex - 1`, which can go negative near the Unix epoch) via integer quotient/remainder
    /// correction rather than floating point.
    public static func dayIndex(unixSecondsUtc: Int64) -> Int64 {
        let quotient = unixSecondsUtc / secondsPerDay
        let remainder = unixSecondsUtc % secondsPerDay
        return remainder < 0 ? quotient - 1 : quotient
    }

    /// HMAC-SHA256(key: `macSpkiFingerprint`, message: `dayIndex` as unsigned 64-bit big-endian),
    /// truncated to its first 8 bytes. `UInt64(bitPattern: dayIndex).bigEndian` (never
    /// `UInt64(dayIndex)`, which traps on a negative `dayIndex`) builds the message bytes.
    public static func compute(macSpkiFingerprint: Data, dayIndex: Int64) -> Data {
        let bigEndianDayIndex = UInt64(bitPattern: dayIndex).bigEndian
        let message = withUnsafeBytes(of: bigEndianDayIndex) { Data($0) }
        let key = SymmetricKey(data: macSpkiFingerprint)
        let digest = Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
        return Data(digest.prefix(idByteCount))
    }

    /// ``compute(macSpkiFingerprint:dayIndex:)``'s bytes, lowercase hex -- the wire form advertised
    /// in the TXT record's `id` field.
    public static func computeHex(macSpkiFingerprint: Data, dayIndex: Int64) -> String {
        compute(macSpkiFingerprint: macSpkiFingerprint, dayIndex: dayIndex)
            .map { String(format: "%02x", $0) }.joined()
    }

    /// The three ids a receiver must accept for `receiverUnixSecondsUtc`'s day, in
    /// `[dayIndex - 1, dayIndex, dayIndex + 1]` order.
    public static func candidateHexIds(
        macSpkiFingerprint: Data,
        receiverUnixSecondsUtc: Int64
    ) -> [String] {
        let today = dayIndex(unixSecondsUtc: receiverUnixSecondsUtc)
        return [today - 1, today, today + 1].map {
            computeHex(macSpkiFingerprint: macSpkiFingerprint, dayIndex: $0)
        }
    }

    /// Throws ``RecognitionError/notRecognized`` unless `advertisedIdHex` is byte-for-byte (i.e.
    /// case-sensitive string) equal to one of `candidateHexIds` -- never canonicalized/lowercased
    /// first.
    public static func recognize(advertisedIdHex: String, candidateHexIds: [String]) throws {
        guard candidateHexIds.contains(advertisedIdHex) else {
            throw RecognitionError.notRecognized
        }
    }
}
