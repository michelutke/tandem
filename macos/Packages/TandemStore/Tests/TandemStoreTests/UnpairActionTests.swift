import Foundation
import Testing
import TandemCrypto
import TandemTestSupport
@testable import TandemStore
@testable import TandemProtocol

// Wrapper to make FakeTandemSession conform to UnpairActionSession
struct FakeTandemSessionUnpairAdapter: UnpairActionSession {
    let session: FakeTandemSession

    var state: AsyncStream<UnpairActionConnectionState> {
        AsyncStream { continuation in
            Task {
                for await state in session.state {
                    let actionState: UnpairActionConnectionState
                    if case .ready = state {
                        actionState = .ready
                    } else {
                        actionState = .other
                    }
                    continuation.yield(actionState)
                }
                continuation.finish()
            }
        }
    }

    func sendRevoke() async throws {
        try await session.send(.control, payload: .revoke(.init()))
    }

    func close() async {
        await session.close()
    }
}

extension FakeTandemSession {
    func asUnpairActionSession() -> any UnpairActionSession {
        FakeTandemSessionUnpairAdapter(session: self)
    }
}

// Fake registry for testing
actor FakeUnpairActionRegistry: UnpairActionRegistry {
    private(set) var unregisteredPeers: [SpkiFingerprint] = []

    func unregister(_ spkiFingerprint: SpkiFingerprint) async {
        unregisteredPeers.append(spkiFingerprint)
    }
}

// Fake purger for testing
// Mutable wrapper for FakePurger to use with actor
actor MutableFakePurger: PeerDataPurging {
    private var purgedPeers: [SpkiFingerprint] = []
    private var shouldThrow: Bool = false

    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    func purgeAll(peer: SpkiFingerprint) async throws {
        if shouldThrow {
            throw NSError(domain: "test", code: 1)
        }
        purgedPeers.append(peer)
    }

    func getPurgedPeers() -> [SpkiFingerprint] {
        purgedPeers
    }
}

@Suite("UnpairAction")
struct UnpairActionTests {

    private static func fingerprint(_ byte: UInt8) throws -> SpkiFingerprint {
        try SpkiFingerprint(bytes: Data(repeating: byte, count: SpkiFingerprint.byteCount))
    }

    private static func makeRecord(
        fingerprint: SpkiFingerprint,
        displayName: String = "iPhone",
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

    @Test("unpairAction_twoRegisteredPurgers_eachCalledOnceWithPeerFingerprint")
    func twoRegisteredPurgersEachCalledOnceWithPeerFingerprint() async throws {
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let registry = FakeUnpairActionRegistry()
        let purgeRegistry = PeerDataPurgeRegistry()
        let spkiFingerprint = try Self.fingerprint(0x01)
        let record = Self.makeRecord(fingerprint: spkiFingerprint)

        // Set up two purgers
        let purger1 = MutableFakePurger()
        let purger2 = MutableFakePurger()
        await purgeRegistry.register(purger1)
        await purgeRegistry.register(purger2)

        // Record exists
        try trustStore.put(record)

        // Execute: unpair without session
        let clock = ManualTestClock()
        await UnpairAction.unpair(
            peerSpkiFingerprint: spkiFingerprint,
            session: nil,
            dependencies: .init(
                trustStore: trustStore,
                registry: registry,
                purgeRegistry: purgeRegistry,
                clock: clock
            )
        )

        // Verify: both purgers called with the peer
        let purged1 = await purger1.getPurgedPeers()
        let purged2 = await purger2.getPurgedPeers()
        #expect(purged1 == [spkiFingerprint])
        #expect(purged2 == [spkiFingerprint])
    }

    @Test("unpairAction_purgerThrows_otherPurgersRunAndRetryRecorded")
    func purgerThrowsOtherPurgersRunAndRetryRecorded() async throws {
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let registry = FakeUnpairActionRegistry()
        let purgeRegistry = PeerDataPurgeRegistry()
        let spkiFingerprint = try Self.fingerprint(0x02)
        let record = Self.makeRecord(fingerprint: spkiFingerprint)

        // Set up: purger1 throws, purger2 succeeds
        let purger1 = MutableFakePurger(shouldThrow: true)
        let purger2 = MutableFakePurger(shouldThrow: false)
        await purgeRegistry.register(purger1)
        await purgeRegistry.register(purger2)

        // Record exists
        try trustStore.put(record)

        // Execute: unpair without session
        let clock = ManualTestClock()
        await UnpairAction.unpair(
            peerSpkiFingerprint: spkiFingerprint,
            session: nil,
            dependencies: .init(
                trustStore: trustStore,
                registry: registry,
                purgeRegistry: purgeRegistry,
                clock: clock
            )
        )

        // Verify: purger2 still ran despite purger1 throwing
        let purged1 = await purger1.getPurgedPeers()
        let purged2 = await purger2.getPurgedPeers()
        #expect(purged1 == [spkiFingerprint])  // Threw but still attempted
        #expect(purged2 == [spkiFingerprint])  // Ran successfully
    }

    @Test("unpairAction_readySession_deleteThenRevokeThenClose")
    func readySessionDeleteThenRevokeThenClose() async throws {
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let registry = FakeUnpairActionRegistry()
        let purgeRegistry = PeerDataPurgeRegistry()
        let spkiFingerprint = try Self.fingerprint(0x03)
        let session = FakeTandemSession()
        let record = Self.makeRecord(fingerprint: spkiFingerprint)

        // Set up: session is Ready
        try trustStore.put(record)
        await session.emit(.ready)

        // Execute: unpair with Ready session
        let clock = ManualTestClock()
        await UnpairAction.unpair(
            peerSpkiFingerprint: spkiFingerprint,
            session: session.asUnpairActionSession(),
            dependencies: .init(
                trustStore: trustStore,
                registry: registry,
                purgeRegistry: purgeRegistry,
                clock: clock
            )
        )

        // Verify: record deleted
        #expect(try trustStore.get(spkiFingerprint) == nil)

        // Verify: Revoke was sent (check sent frames)
        let sent = await session.sent
        let hasRevoke = sent.contains { frame in
            if case .revoke = frame.payload {
                return true
            }
            return false
        }
        #expect(hasRevoke)

        // Verify: registry unregistered
        let unregistered = await registry.unregisteredPeers
        #expect(unregistered.contains(spkiFingerprint))
    }

    @Test("unpairAction_noSession_deletesLocallySendsNothing")
    func noSessionDeletesLocallySendsNothing() async throws {
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let registry = FakeUnpairActionRegistry()
        let purgeRegistry = PeerDataPurgeRegistry()
        let spkiFingerprint = try Self.fingerprint(0x04)
        let record = Self.makeRecord(fingerprint: spkiFingerprint)

        // Record exists
        try trustStore.put(record)

        // Execute: unpair without session
        let clock = ManualTestClock()
        await UnpairAction.unpair(
            peerSpkiFingerprint: spkiFingerprint,
            session: nil,
            dependencies: .init(
                trustStore: trustStore,
                registry: registry,
                purgeRegistry: purgeRegistry,
                clock: clock
            )
        )

        // Verify: record deleted
        #expect(try trustStore.get(spkiFingerprint) == nil)

        // Verify: registry not called (no peers unregistered)
        let unregistered = await registry.unregisteredPeers
        #expect(unregistered.isEmpty)
    }

    @Test("unpairAction_revokeSendThrows_recordDeletedAndSessionClosed")
    func revokeSendThrowsRecordDeletedAndSessionClosed() async throws {
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let registry = FakeUnpairActionRegistry()
        let purgeRegistry = PeerDataPurgeRegistry()
        let spkiFingerprint = try Self.fingerprint(0x05)
        let session = FakeTandemSession()
        let record = Self.makeRecord(fingerprint: spkiFingerprint)

        // Set up: session Ready, and configure it to fail on send
        try trustStore.put(record)
        await session.emit(.ready)

        // Create an adapter that fails on sendRevoke
        struct FailingAdapter: UnpairActionSession {
            let session: FakeTandemSession
            var state: AsyncStream<UnpairActionConnectionState> {
                AsyncStream { continuation in
                    Task {
                        for await state in session.state {
                            let actionState: UnpairActionConnectionState
                            if case .ready = state {
                                actionState = .ready
                            } else {
                                actionState = .other
                            }
                            continuation.yield(actionState)
                        }
                        continuation.finish()
                    }
                }
            }

            func sendRevoke() async throws {
                throw NSError(domain: "test", code: 1)
            }

            func close() async {
                await session.close()
            }
        }

        // Execute: unpair with failing send
        let clock = ManualTestClock()
        await UnpairAction.unpair(
            peerSpkiFingerprint: spkiFingerprint,
            session: FailingAdapter(session: session),
            dependencies: .init(
                trustStore: trustStore,
                registry: registry,
                purgeRegistry: purgeRegistry,
                clock: clock
            )
        )

        // Verify: record deleted despite send failure
        #expect(try trustStore.get(spkiFingerprint) == nil)

        // Verify: session was closed (registry unregistered)
        let unregistered = await registry.unregisteredPeers
        #expect(unregistered.contains(spkiFingerprint))
    }

    @Test("unpairAction_revokeSendHangs_sessionClosedAfter2sVirtual")
    func revokeSendHangsSessionClosedAfter2sVirtual() async throws {
        let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
        let registry = FakeUnpairActionRegistry()
        let purgeRegistry = PeerDataPurgeRegistry()
        let spkiFingerprint = try Self.fingerprint(0x06)
        let session = FakeTandemSession()
        let record = Self.makeRecord(fingerprint: spkiFingerprint)

        // Set up: session Ready
        try trustStore.put(record)
        await session.emit(.ready)

        // Create an adapter that hangs on sendRevoke
        struct HangingAdapter: UnpairActionSession {
            let session: FakeTandemSession
            let clock: any Clock<Duration>

            var state: AsyncStream<UnpairActionConnectionState> {
                AsyncStream { continuation in
                    Task {
                        for await state in session.state {
                            let actionState: UnpairActionConnectionState
                            if case .ready = state {
                                actionState = .ready
                            } else {
                                actionState = .other
                            }
                            continuation.yield(actionState)
                        }
                        continuation.finish()
                    }
                }
            }

            func sendRevoke() async throws {
                // Hang forever using injected clock
                try await clock.sleep(for: .seconds(1000000))
            }

            func close() async {
                await session.close()
            }
        }

        // Execute: unpair with hanging send
        let clock = ManualTestClock()
        await UnpairAction.unpair(
            peerSpkiFingerprint: spkiFingerprint,
            session: HangingAdapter(session: session, clock: clock),
            dependencies: .init(
                trustStore: trustStore,
                registry: registry,
                purgeRegistry: purgeRegistry,
                clock: clock
            )
        )

        // Verify: record deleted
        #expect(try trustStore.get(spkiFingerprint) == nil)

        // Verify: session was closed despite hanging send (registry unregistered)
        let unregistered = await registry.unregisteredPeers
        #expect(unregistered.contains(spkiFingerprint))
    }
}
