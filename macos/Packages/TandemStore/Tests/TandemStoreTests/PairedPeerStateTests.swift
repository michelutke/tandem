import Foundation
import Testing
import TandemCrypto
import TandemTestSupport
@testable import TandemStore

@MainActor
@Suite("PairedPeerState")
struct PairedPeerStateTests {
    private static func record(name: String) throws -> PeerRecord {
        PeerRecord(
            fingerprint: try SpkiFingerprint(bytes: Data(repeating: 0x07, count: SpkiFingerprint.byteCount)),
            displayName: name,
            pairedAt: Date(timeIntervalSince1970: 0),
            lastSeen: Date(timeIntervalSince1970: 0),
            capabilities: []
        )
    }

    @Test
    func pairedPeerState_emptyTrustStore_displayNameNil() {
        let state = PairedPeerState(trustStore: TrustStore(keychainStore: InMemoryKeychainStore()))

        #expect(state.displayName == nil)
    }

    @Test
    func pairedPeerState_refreshAfterPairingCommit_publishesPeerName() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let state = PairedPeerState(trustStore: store)

        try store.put(try Self.record(name: "Pixel"))
        state.refresh()

        #expect(state.displayName == "Pixel")
    }

    @Test
    func pairedPeerState_refreshAfterUnpair_publishesNil() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let record = try Self.record(name: "Pixel")
        try store.put(record)
        let state = PairedPeerState(trustStore: store)
        #expect(state.displayName == "Pixel")

        try store.delete(record.fingerprint)
        state.refresh()

        #expect(state.displayName == nil)
    }
}
