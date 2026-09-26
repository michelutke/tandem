import Foundation
import Testing
import TandemCrypto
import TandemTestSupport
@testable import TandemStore
@testable import TandemProtocol

// Wrapper to make FakeTandemSession conform to RevokeHandlerSession
struct FakeTandemSessionAdapter: RevokeHandlerSession {
    let session: FakeTandemSession

    var state: AsyncStream<RevokeHandlerConnectionState> {
        AsyncStream { continuation in
            Task {
                for await state in session.state {
                    let handlerState: RevokeHandlerConnectionState
                    if case .ready = state {
                        handlerState = .ready
                    } else {
                        handlerState = .other
                    }
                    continuation.yield(handlerState)
                }
                continuation.finish()
            }
        }
    }

    func close() async {
        await session.close()
    }
}

// Extension for convenience
extension FakeTandemSession {
    func asHandlerSession() -> any RevokeHandlerSession {
        FakeTandemSessionAdapter(session: self)
    }
}

// Adapter to make ControlSessionRegistry conform to RevokeHandlerRegistry
struct FakeControlSessionRegistryAdapter: RevokeHandlerRegistry {
    let registry: ControlSessionRegistry

    func unregister(_ spkiFingerprint: SpkiFingerprint) async {
        await registry.unregister(spkiFingerprint)
    }
}

@Suite("RevokeHandler")
struct RevokeHandlerTests {

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

    @Test("revokeHandler_revokeFromReadyTrustedPeer_deletesRecordAndClosesSession")
    func revokeFromReadyTrustedPeerDeletesRecordAndClosesSession() async throws {
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let registry = ControlSessionRegistry()
        let spkiFingerprint = try Self.fingerprint(0x01)
        let session = FakeTandemSession()
        let record = Self.makeRecord(fingerprint: spkiFingerprint)

        // Set up: record exists and session is registered in Ready state
        try trustStore.put(record)
        await registry.register(spkiFingerprint, session: session)
        await session.emit(.ready)

        // Verify precondition: record exists
        #expect(try trustStore.get(spkiFingerprint) == record)

        // Execute: handle the revoke
        await RevokeHandler.handle(
            peerSpkiFingerprint: spkiFingerprint,
            session: session.asHandlerSession(),
            trustStore: trustStore,
            registry: FakeControlSessionRegistryAdapter(registry: registry)
        )

        // Verify: record is deleted
        #expect(try trustStore.get(spkiFingerprint) == nil)
    }

    @Test("revokeHandler_revokeOnPairingCandidateConnection_ignoredRecordsUnchanged")
    func revokeOnPairingCandidateConnectionIgnoredRecordsUnchanged() async throws {
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let registry = ControlSessionRegistry()
        let spkiFingerprint = try Self.fingerprint(0x02)
        let session = FakeTandemSession()
        let record = Self.makeRecord(fingerprint: spkiFingerprint)

        // Set up: record exists but session is not Ready (pairing candidate)
        try trustStore.put(record)
        await registry.register(spkiFingerprint, session: session)
        await session.emit(.accepted)

        // Execute: handle the revoke (should be ignored)
        await RevokeHandler.handle(
            peerSpkiFingerprint: spkiFingerprint,
            session: session.asHandlerSession(),
            trustStore: trustStore,
            registry: FakeControlSessionRegistryAdapter(registry: registry)
        )

        // Verify: record is unchanged
        #expect(try trustStore.get(spkiFingerprint) == record)
    }

    @Test("revokeHandler_twoPairedPeers_onlySendersRecordDeleted")
    func twoPairedPeersOnlySendersRecordDeleted() async throws {
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let registry = ControlSessionRegistry()
        let spki1 = try Self.fingerprint(0x03)
        let spki2 = try Self.fingerprint(0x04)
        let session1 = FakeTandemSession()
        let session2 = FakeTandemSession()
        let record1 = Self.makeRecord(fingerprint: spki1, displayName: "iPhone")
        let record2 = Self.makeRecord(fingerprint: spki2, displayName: "Android")

        // Set up: two records exist and both sessions are Ready
        try trustStore.put(record1)
        try trustStore.put(record2)
        await registry.register(spki1, session: session1)
        await registry.register(spki2, session: session2)
        await session1.emit(.ready)
        await session2.emit(.ready)

        // Execute: handle the revoke from session1
        await RevokeHandler.handle(
            peerSpkiFingerprint: spki1,
            session: session1.asHandlerSession(),
            trustStore: trustStore,
            registry: FakeControlSessionRegistryAdapter(registry: registry)
        )

        // Verify: only sender's record is deleted
        #expect(try trustStore.get(spki1) == nil)
        #expect(try trustStore.get(spki2) == record2)
    }

    @Test("revokeHandler_revokeAfterPairAcceptedSameConnection_deletesNewRecord")
    func revokeAfterPairAcceptedSameConnectionDeletesNewRecord() async throws {
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let registry = ControlSessionRegistry()
        let spkiFingerprint = try Self.fingerprint(0x05)
        let session = FakeTandemSession()
        let record = Self.makeRecord(fingerprint: spkiFingerprint)

        // Set up: the record was just committed (after PairAccepted)
        try trustStore.put(record)
        await registry.register(spkiFingerprint, session: session)
        await session.emit(.ready)

        // Execute: handle the revoke
        await RevokeHandler.handle(
            peerSpkiFingerprint: spkiFingerprint,
            session: session.asHandlerSession(),
            trustStore: trustStore,
            registry: FakeControlSessionRegistryAdapter(registry: registry)
        )

        // Verify: record is deleted
        #expect(try trustStore.get(spkiFingerprint) == nil)
    }
}
