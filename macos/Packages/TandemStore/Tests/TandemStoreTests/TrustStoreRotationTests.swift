import Foundation
import Testing
import TandemCrypto
import TandemTestSupport
@testable import TandemStore

@Suite("TrustStore rotation")
struct TrustStoreRotationTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    private static func fingerprint(_ byte: UInt8) throws -> SpkiFingerprint {
        try SpkiFingerprint(bytes: Data(repeating: byte, count: SpkiFingerprint.byteCount))
    }

    private static func record(_ byte: UInt8) throws -> PeerRecord {
        PeerRecord(
            fingerprint: try fingerprint(byte),
            displayName: "Phone \(byte)",
            pairedAt: Date(timeIntervalSince1970: 0),
            lastSeen: Date(timeIntervalSince1970: 0),
            capabilities: []
        )
    }

    @Test
    func rotatePrimary_validRecord_newPrimaryAndOldPinGraceOnly() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let record = try Self.record(0x01)
        let newFingerprint = try Self.fingerprint(0x02)
        try store.put(record)

        try store.rotatePrimary(of: record, to: newFingerprint, now: Self.now)

        let rotated = try #require(try store.get(newFingerprint))
        #expect(rotated.gracePin?.fingerprint == record.fingerprint)
        #expect(rotated.gracePin?.expiresAt == Self.now.addingTimeInterval(7 * 24 * 60 * 60))
        #expect(try store.get(record.fingerprint) == nil)
        #expect(try store.list().count == 1)
    }

    @Test
    func authenticatedPeer_afterRotation_primaryAndGraceResolveToSameRecord() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let record = try Self.record(0x01)
        let newFingerprint = try Self.fingerprint(0x02)
        try store.put(record)
        try store.rotatePrimary(of: record, to: newFingerprint, now: Self.now)

        let viaNew = try store.authenticatedPeer(newFingerprint, now: Self.now)
        let viaOld = try store.authenticatedPeer(record.fingerprint, now: Self.now)

        #expect(viaNew?.pin == .primary)
        #expect(viaOld?.pin == .grace)
        #expect(viaNew?.record == viaOld?.record)
    }

    @Test
    func authenticatedPeer_graceExpired_returnsNil() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let record = try Self.record(0x01)
        try store.put(record)
        try store.rotatePrimary(of: record, to: try Self.fingerprint(0x02), now: Self.now)
        let afterExpiry = Self.now.addingTimeInterval(7 * 24 * 60 * 60)

        #expect(try store.authenticatedPeer(record.fingerprint, now: afterExpiry) == nil)
    }

    @Test
    func holdsPin_primaryAndGrace_true() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let record = try Self.record(0x01)
        try store.put(record)
        try store.rotatePrimary(of: record, to: try Self.fingerprint(0x02), now: Self.now)

        #expect(try store.holdsPin(try Self.fingerprint(0x01)))
        #expect(try store.holdsPin(try Self.fingerprint(0x02)))
        #expect(try !store.holdsPin(try Self.fingerprint(0x03)))
    }

    @Test
    func purgeGracePin_byNewPrimarySession_removesGrace() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let record = try Self.record(0x01)
        let newFingerprint = try Self.fingerprint(0x02)
        try store.put(record)
        try store.rotatePrimary(of: record, to: newFingerprint, now: Self.now)

        try store.purgeGracePin(authenticatedByPrimary: newFingerprint)

        #expect(try store.get(newFingerprint)?.gracePin == nil)
        #expect(try store.authenticatedPeer(record.fingerprint, now: Self.now) == nil)
    }

    @Test
    func purgeGracePin_byGraceSessionClose_removesGraceKeepsPrimary() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let record = try Self.record(0x01)
        let newFingerprint = try Self.fingerprint(0x02)
        try store.put(record)
        try store.rotatePrimary(of: record, to: newFingerprint, now: Self.now)

        try store.purgeGracePin(authenticatedByGrace: record.fingerprint)

        #expect(try store.get(newFingerprint)?.gracePin == nil)
        #expect(try store.authenticatedPeer(newFingerprint, now: Self.now)?.pin == .primary)
    }

    @Test
    func purgeExpiredGracePins_onlyExpiredPurged() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let expiring = try Self.record(0x01)
        let fresh = try Self.record(0x11)
        try store.put(expiring)
        try store.put(fresh)
        try store.rotatePrimary(of: expiring, to: try Self.fingerprint(0x02), now: Self.now)
        try store.rotatePrimary(of: fresh, to: try Self.fingerprint(0x12), now: Self.now.addingTimeInterval(3600))

        try store.purgeExpiredGracePins(now: Self.now.addingTimeInterval(7 * 24 * 60 * 60))

        #expect(try store.get(try Self.fingerprint(0x02))?.gracePin == nil)
        #expect(try store.get(try Self.fingerprint(0x12))?.gracePin != nil)
    }

    @Test
    func rotatePrimary_keychainFailsMidSwap_recordUnchanged() throws {
        let keychain = InMemoryKeychainStore()
        let store = TrustStore(keychainStore: keychain)
        let record = try Self.record(0x01)
        try store.put(record)

        keychain.failNextOperation(with: .locked)
        #expect(throws: KeychainError.locked) {
            try store.rotatePrimary(of: record, to: try Self.fingerprint(0x02), now: Self.now)
        }

        #expect(try store.get(record.fingerprint) == record)
        #expect(try store.get(try Self.fingerprint(0x02)) == nil)
    }

    @Test
    func rotatePrimary_otherPeerRecord_unchanged() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let rotating = try Self.record(0x01)
        let other = try Self.record(0x21)
        try store.put(rotating)
        try store.put(other)

        try store.rotatePrimary(of: rotating, to: try Self.fingerprint(0x02), now: Self.now)

        #expect(try store.get(other.fingerprint) == other)
    }

    @Test
    func delete_rotatedPeerByNewPrimary_removesRecord() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let record = try Self.record(0x01)
        let newFingerprint = try Self.fingerprint(0x02)
        try store.put(record)
        try store.rotatePrimary(of: record, to: newFingerprint, now: Self.now)

        try store.delete(newFingerprint)

        #expect(try store.list().isEmpty)
    }

    @Test
    func decode_v1RecordJson_defaultsRecordIdAndNoGrace() throws {
        let fingerprint = try Self.fingerprint(0x05)
        let v1Json = """
        {"fingerprint":"\(fingerprint.bytes.base64EncodedString())","displayName":"Old",
        "pairedAt":0,"lastSeen":0,"capabilities":[]}
        """

        let record = try JSONDecoder().decode(PeerRecord.self, from: Data(v1Json.utf8))

        #expect(record.recordId == fingerprint)
        #expect(record.gracePin == nil)
    }

    @Test
    func migrationV1ToV2_rotatedRecordLaterReadable_graceFieldsDefaulted() throws {
        let keychain = InMemoryKeychainStore()
        let record = try Self.record(0x07)
        try keychain.addGenericPassword(
            service: TrustStore.peerRecordService,
            account: record.fingerprint.hexString,
            data: try JSONEncoder().encode(record),
            accessibility: .afterFirstUnlockThisDeviceOnly
        )

        try TrustStore.runMigrationV1ToV2(keychainStore: keychain)

        let store = TrustStore(keychainStore: keychain)
        let migrated = try #require(try store.get(record.fingerprint))
        #expect(migrated.gracePin == nil)
        #expect(migrated.recordId == record.fingerprint)
        #expect(try store.schemaVersion() == 2)
    }
}
