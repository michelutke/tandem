import Foundation
import Testing
import TandemCrypto
import TandemStore
import TandemTestSupport
@testable import TandemTransport

/// ``TandemTrustStoreReader`` (E12-02/E13-06): the production ``TrustStoreReader`` adapter over
/// `TandemStore.TrustStore`, unit-tested against `InMemoryKeychainStore` -- never a real Keychain.
@Suite("TandemTrustStoreReader")
struct TandemTrustStoreReaderTests {

    private static func fingerprint(_ byte: UInt8) throws -> SpkiFingerprint {
        try SpkiFingerprint(bytes: Data(repeating: byte, count: SpkiFingerprint.byteCount))
    }

    private static func makeRecord(fingerprint: SpkiFingerprint) -> PeerRecord {
        PeerRecord(
            fingerprint: fingerprint,
            displayName: "MacBook",
            pairedAt: Date(timeIntervalSince1970: 0),
            lastSeen: Date(timeIntervalSince1970: 0),
            capabilities: ["clipboard"]
        )
    }

    @Test
    func tandemTrustStoreReader_pairedFingerprint_containsTrue() throws {
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let fingerprint = try Self.fingerprint(0x01)
        try trustStore.put(Self.makeRecord(fingerprint: fingerprint))
        let reader = TandemTrustStoreReader(trustStore: trustStore)

        #expect(try reader.contains(fingerprint))
    }

    @Test
    func tandemTrustStoreReader_unknownFingerprint_containsFalse() throws {
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        try trustStore.put(Self.makeRecord(fingerprint: try Self.fingerprint(0x02)))
        let reader = TandemTrustStoreReader(trustStore: trustStore)

        #expect(try reader.contains(Self.fingerprint(0x03)) == false)
    }

    @Test
    func tandemTrustStoreReader_matchAmongSeveralRecords_containsTrue() throws {
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let target = try Self.fingerprint(0x04)
        try trustStore.put(Self.makeRecord(fingerprint: try Self.fingerprint(0x05)))
        try trustStore.put(Self.makeRecord(fingerprint: target))
        try trustStore.put(Self.makeRecord(fingerprint: try Self.fingerprint(0x06)))
        let reader = TandemTrustStoreReader(trustStore: trustStore)

        #expect(try reader.contains(target))
    }

    @Test
    func tandemTrustStoreReader_emptyTrustStore_containsFalse() throws {
        let reader = TandemTrustStoreReader(trustStore: TrustStore(keychainStore: InMemoryKeychainStore()))

        #expect(try reader.contains(Self.fingerprint(0x07)) == false)
    }

    @Test
    func tandemTrustStoreReader_keychainLocked_throwsRatherThanFalse() throws {
        let keychain = InMemoryKeychainStore()
        let trustStore = TrustStore(keychainStore: keychain)
        let reader = TandemTrustStoreReader(trustStore: trustStore)
        keychain.failNextOperation(with: .locked)

        #expect(throws: KeychainError.locked) {
            _ = try reader.contains(try Self.fingerprint(0x08))
        }
    }
}
