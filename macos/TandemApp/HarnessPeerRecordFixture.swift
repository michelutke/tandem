#if DEBUG
import Foundation
import TandemCrypto
import TandemStore

/// JSON fixture for `-HarnessSeedTrust <path>`: hex/ISO 8601 fields instead of `PeerRecord`'s own
/// Foundation `Codable` encoding (raw bytes as base64, dates as `timeIntervalSinceReferenceDate`),
/// so the CI driver script can generate the fixture without reproducing Foundation's date/data
/// encoding. Split out of `HarnessHooks.swift` purely to keep that file under this repo's
/// `file_length` lint budget.
struct HarnessPeerRecordFixture: Decodable {
    let fingerprintHex: String
    let displayName: String
    let pairedAt: String
    let lastSeen: String
    let capabilities: [String]

    enum FixtureError: Error {
        case invalidFingerprintHex
        case invalidDate
    }

    func makePeerRecord() throws -> PeerRecord {
        guard let fingerprintBytes = Data(harnessHexString: fingerprintHex) else {
            throw FixtureError.invalidFingerprintHex
        }
        let formatter = ISO8601DateFormatter()
        guard let pairedAtDate = formatter.date(from: pairedAt),
              let lastSeenDate = formatter.date(from: lastSeen) else {
            throw FixtureError.invalidDate
        }
        return PeerRecord(
            fingerprint: try SpkiFingerprint(bytes: fingerprintBytes),
            displayName: displayName,
            pairedAt: pairedAtDate,
            lastSeen: lastSeenDate,
            capabilities: capabilities
        )
    }
}

extension Data {
    init?(harnessHexString hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
#endif
