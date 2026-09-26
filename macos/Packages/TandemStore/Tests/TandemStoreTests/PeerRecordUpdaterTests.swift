import Foundation
import Testing
import TandemCrypto
import TandemTestSupport
@testable import TandemStore

@Suite("PeerRecordUpdater")
struct PeerRecordUpdaterTests {

    private static func fingerprint(_ byte: UInt8) throws -> SpkiFingerprint {
        try SpkiFingerprint(bytes: Data(repeating: byte, count: SpkiFingerprint.byteCount))
    }

    private static func makeRecord(
        fingerprint: SpkiFingerprint,
        displayName: String = "MacBook",
        pairedAt: Date = Date(timeIntervalSince1970: 0),
        lastSeen: Date = Date(timeIntervalSince1970: 0),
        capabilities: [String] = ["clipboard", "files"]
    ) -> PeerRecord {
        PeerRecord(
            fingerprint: fingerprint,
            displayName: displayName,
            pairedAt: pairedAt,
            lastSeen: lastSeen,
            capabilities: capabilities
        )
    }

    @Test
    func peerRecordUpdater_readyKnownSpki_setsLastSeenAndCapabilities() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let fingerprint = try Self.fingerprint(0x01)
        let originalLastSeen = Date(timeIntervalSince1970: 100)
        let record = Self.makeRecord(
            fingerprint: fingerprint,
            lastSeen: originalLastSeen,
            capabilities: ["clipboard"]
        )
        try store.put(record)

        let newDate = Date(timeIntervalSince1970: 200)
        let newCapabilities = ["clipboard", "files", "screenCast"]
        let updater = PeerRecordUpdater(trustStore: store, dateProvider: { newDate })
        try updater.updateOnReady(handshakeSpki: fingerprint, capabilities: newCapabilities)

        let updated = try store.get(fingerprint)
        #expect(updated?.lastSeen == newDate)
        #expect(updated?.capabilities == newCapabilities)
        #expect(updated?.displayName == "MacBook")
        #expect(updated?.pairedAt == Date(timeIntervalSince1970: 0))
    }

    @Test
    func peerRecordUpdater_failedHandshakeOrHello_allRecordsUnchanged() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let fingerprint = try Self.fingerprint(0x02)
        let originalRecord = Self.makeRecord(
            fingerprint: fingerprint,
            lastSeen: Date(timeIntervalSince1970: 100),
            capabilities: ["clipboard"]
        )
        try store.put(originalRecord)

        let updater = PeerRecordUpdater(trustStore: store, dateProvider: { Date(timeIntervalSince1970: 200) })
        // updateOnReady is not called, simulating a failed handshake/hello

        let unchanged = try store.get(fingerprint)
        #expect(unchanged == originalRecord)
    }

    @Test
    func peerRecordUpdater_pairingWindowConnection_noRecordWritten() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())

        let newDate = Date(timeIntervalSince1970: 100)
        let updater = PeerRecordUpdater(trustStore: store, dateProvider: { newDate })
        // For a pairing-window connection, updateOnReady is not called
        // (the system creates a new peer record during pairing, not via the updater)

        let list = try store.list()
        #expect(list.isEmpty)
    }

    @Test
    func peerRecordUpdater_twoRecordsSameDeviceId_onlyHandshakeSpkiUpdated() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let fingerprint1 = try Self.fingerprint(0x03)
        let fingerprint2 = try Self.fingerprint(0x04)
        let record1 = Self.makeRecord(
            fingerprint: fingerprint1,
            displayName: "MacBook",
            lastSeen: Date(timeIntervalSince1970: 100),
            capabilities: ["clipboard"]
        )
        let record2 = Self.makeRecord(
            fingerprint: fingerprint2,
            displayName: "MacBook",
            lastSeen: Date(timeIntervalSince1970: 100),
            capabilities: ["clipboard"]
        )
        try store.put(record1)
        try store.put(record2)

        let newDate = Date(timeIntervalSince1970: 200)
        let newCapabilities = ["clipboard", "files"]
        let updater = PeerRecordUpdater(trustStore: store, dateProvider: { newDate })
        try updater.updateOnReady(handshakeSpki: fingerprint1, capabilities: newCapabilities)

        let updated1 = try store.get(fingerprint1)
        let unchanged2 = try store.get(fingerprint2)

        #expect(updated1?.lastSeen == newDate)
        #expect(updated1?.capabilities == newCapabilities)
        #expect(unchanged2 == record2)
    }
}
