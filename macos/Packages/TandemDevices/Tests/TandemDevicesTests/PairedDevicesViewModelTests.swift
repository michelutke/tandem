import Foundation
import Testing
import TandemCrypto
import TandemStore
import TandemTestSupport
@testable import TandemDevices

/// The Mac main window's Devices screen view model (E14-14). Every fixture here drives a real
/// ``TrustStore`` (over `InMemoryKeychainStore`, same as ``TrustStoreTests``) and a fake `unpair`
/// closure standing in for E14-13's `UnpairAction`, which hasn't landed yet.
@Suite("PairedDevicesViewModel")
@MainActor
struct PairedDevicesViewModelTests {

    /// Signals when `unpair` was invoked, and with which fingerprint -- lets a test wait
    /// deterministically for the background call ``PairedDevicesViewModel/confirmRevoke()``
    /// starts, instead of racing it with a sleep (the same continuation-based pattern
    /// `ChannelMultiplexerTests` and friends use).
    private actor UnpairSignal {
        private var continuation: CheckedContinuation<SpkiFingerprint, Never>?
        private var pendingFingerprint: SpkiFingerprint?

        func called(_ fingerprint: SpkiFingerprint) {
            if let continuation {
                continuation.resume(returning: fingerprint)
                self.continuation = nil
            } else {
                pendingFingerprint = fingerprint
            }
        }

        func waitForCall() async -> SpkiFingerprint {
            if let pendingFingerprint {
                return pendingFingerprint
            }
            return await withCheckedContinuation { continuation = $0 }
        }
    }

    private static func fingerprint(_ byte: UInt8) throws -> SpkiFingerprint {
        try SpkiFingerprint(bytes: Data(repeating: byte, count: SpkiFingerprint.byteCount))
    }

    private static func makeRecord(
        fingerprint: SpkiFingerprint,
        displayName: String,
        lastSeen: Date
    ) -> PeerRecord {
        PeerRecord(
            fingerprint: fingerprint,
            displayName: displayName,
            pairedAt: lastSeen,
            lastSeen: lastSeen,
            capabilities: []
        )
    }

    private static func makeViewModel(
        trustStore: TrustStore,
        now: Date,
        unpair: @escaping @Sendable (SpkiFingerprint) async throws -> Void = { _ in }
    ) -> PairedDevicesViewModel {
        PairedDevicesViewModel(trustStore: trustStore, dateProvider: { now }, unpair: unpair)
    }

    @Test
    func pairedDevicesViewModel_twoTrustRecords_twoRowsWithNames() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let now = Date(timeIntervalSince1970: 1_000_000)
        try store.put(Self.makeRecord(fingerprint: try Self.fingerprint(0x01), displayName: "Pixel 8", lastSeen: now))
        try store.put(Self.makeRecord(fingerprint: try Self.fingerprint(0x02), displayName: "iPhone", lastSeen: now))

        let viewModel = Self.makeViewModel(trustStore: store, now: now)

        #expect(viewModel.rows.count == 2)
        #expect(Set(viewModel.rows.map(\.displayName)) == ["Pixel 8", "iPhone"])
    }

    @Test
    func pairedDevicesViewModel_lastSeen5MinutesAgo_rowReadsFiveMinutesAgo() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fiveMinutesAgo = now.addingTimeInterval(-5 * 60)
        try store.put(
            Self.makeRecord(fingerprint: try Self.fingerprint(0x03), displayName: "Pixel 8", lastSeen: fiveMinutesAgo)
        )

        let viewModel = Self.makeViewModel(trustStore: store, now: now)

        let row = try #require(viewModel.rows.first)
        #expect(row.lastSeenText == "5 minutes ago")
    }

    @Test
    func pairedDevicesViewModel_revokeTapped_rowRemovedBeforeRevokeCompletes() async throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fingerprint = try Self.fingerprint(0x04)
        try store.put(Self.makeRecord(fingerprint: fingerprint, displayName: "Pixel 8", lastSeen: now))

        let signal = UnpairSignal()
        let viewModel = Self.makeViewModel(trustStore: store, now: now) { calledFingerprint in
            await signal.called(calledFingerprint)
        }

        let row = try #require(viewModel.rows.first)
        viewModel.requestRevoke(row)
        viewModel.confirmRevoke()

        // The row is gone the instant confirmRevoke() returns -- before the (still-suspended)
        // unpair call this asserts happened below has even resumed.
        #expect(viewModel.rows.isEmpty)

        let calledFingerprint = await signal.waitForCall()
        #expect(calledFingerprint == fingerprint)
    }

    @Test
    func pairedDevicesViewModel_cancelRevoke_rowStaysAndPendingCleared() throws {
        let store = TrustStore(keychainStore: InMemoryKeychainStore())
        let now = Date(timeIntervalSince1970: 1_000_000)
        try store.put(
            Self.makeRecord(fingerprint: try Self.fingerprint(0x05), displayName: "Pixel 8", lastSeen: now)
        )

        let viewModel = Self.makeViewModel(trustStore: store, now: now)

        let row = try #require(viewModel.rows.first)
        viewModel.requestRevoke(row)
        viewModel.cancelRevoke()

        #expect(viewModel.rows.count == 1)
        #expect(viewModel.pendingRevoke == nil)
    }
}
