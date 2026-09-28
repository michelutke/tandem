import Foundation
import Testing
import TandemCrypto
import TandemDevices
import TandemStore
@testable import TandemApp
@testable import TandemProtocol

/// E14-26 tdd (unit): proves ``AppComposition/makeUnpairAction(trustStore:sessionRegistry:purgeRegistry:clock:)``
/// -- the closure ``AppComposition/makePairedDevicesViewModel(lifecycle:dateProvider:clock:)`` wires
/// into the real Devices screen's ``PairedDevicesViewModel`` (E14-14) -- actually calls
/// `TandemStore`'s own `UnpairAction`: deleting the local trust record and, since the peer here has
/// a live registered session, sending it `Revoke` and closing/unregistering that session. Before
/// E14-26, `PairedDevicesViewModel` was never composed with a real `unpair` outside its own tests
/// (`TandemDevicesTests`' fake closure), so the Mac couldn't revoke a phone in production at all.
@Suite("PairedDevicesViewModel composition (E14-26)")
@MainActor
struct PairedDevicesCompositionTests {

    private static func fingerprint(_ byte: UInt8) throws -> SpkiFingerprint {
        try SpkiFingerprint(bytes: Data(repeating: byte, count: SpkiFingerprint.byteCount))
    }

    @Test
    func pairedDevicesViewModel_unpairSelected_sendsRevokeAndDeletesLocalTrust() async throws {
        let keychain = try TemporaryFileKeychain()
        defer { keychain.cleanup() }
        let trustStore = TrustStore(keychainStore: keychain.store)
        let fingerprint = try Self.fingerprint(0x11)
        try trustStore.put(
            PeerRecord(
                fingerprint: fingerprint,
                displayName: "Pixel 8",
                pairedAt: Date(timeIntervalSince1970: 0),
                lastSeen: Date(timeIntervalSince1970: 0),
                capabilities: []
            )
        )

        // This peer is currently connected -- registered exactly the way `NWListenerFactory`
        // registers a real `.trusted` session reaching Ready (E12-19).
        let sessionRegistry = ControlSessionRegistry()
        let session = FakeTandemSession()
        await sessionRegistry.register(fingerprint, session: session)
        await session.emit(.ready)

        let purgeRegistry = PeerDataPurgeRegistry()
        let clock = ContinuousClock()

        let viewModel = PairedDevicesViewModel(
            trustStore: trustStore,
            dateProvider: { Date(timeIntervalSince1970: 0) },
            unpair: AppComposition.makeUnpairAction(
                trustStore: trustStore,
                sessionRegistry: sessionRegistry,
                purgeRegistry: purgeRegistry,
                clock: clock
            )
        )

        let row = try #require(viewModel.rows.first)
        viewModel.requestRevoke(row)
        viewModel.confirmRevoke()

        // The row disappears immediately (optimistic on local delete, E14-14); `unpair` itself
        // keeps running in the background (`sendRevoke()` racing a 2s send timeout in a task
        // group), so poll its effects instead of racing a fixed sleep. `sendRevoke()` on this
        // real `FakeTandemSession` resolves near-instantly, well inside that 2s timeout.
        #expect(viewModel.rows.isEmpty)
        let deletedInTime = await Self.waitUntil(maxPolls: 200, pollIntervalMs: 10) {
            let record: PeerRecord?? = try? trustStore.get(fingerprint)
            return (record ?? nil) == nil
        }
        #expect(deletedInTime)

        #expect(try trustStore.get(fingerprint) == nil)

        let sent = await session.sent
        let sentRevoke = sent.contains { frame in
            if case .revoke = frame.payload { return true }
            return false
        }
        #expect(sentRevoke)

        let stillRegistered = await sessionRegistry.session(for: fingerprint) != nil
        #expect(!stillRegistered)
    }

    /// Polls `condition` up to `maxPolls` times, `pollIntervalMs` apart, using
    /// `DispatchQueue.asyncAfter` rather than an unbounded-clock sleep or wall-clock read (banned by the
    /// `injected_clock_only` SwiftLint rule in this package; mirrors
    /// `TandemTransportTests`' own `SpyControlSessionRegistry.waitForRegistration` idiom).
    private static func waitUntil(
        maxPolls: Int,
        pollIntervalMs: Int,
        condition: @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<maxPolls {
            if await condition() { return true }
            await Self.sleepOnGlobalQueue(milliseconds: pollIntervalMs)
        }
        return await condition()
    }

    private static func sleepOnGlobalQueue(milliseconds: Int) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                continuation.resume()
            }
        }
    }
}

/// A throwaway on-disk keychain for this file only (E10-07b, D-75): a fresh directory under
/// `FileManager.default.temporaryDirectory`, a random per-instance password, and a real
/// `SecItemKeychainStore` already pointed at it via `KeychainTarget.file` -- never the login
/// keychain, so this test never prompts. Duplicated from `TandemTransportTests/TemporaryKeychain.swift`
/// (this repo's own established per-test-target-copy convention, see that file's kdoc) rather than
/// adding `TandemTestSupport`'s `InMemoryKeychainStore` as a project-level dependency here, which
/// hit an unrelated Xcode `PackageFrameworks`/X509 build-graph issue in this environment. Callers
/// must call `cleanup()` (ideally in `defer`) to delete the keychain file and its directory.
private final class TemporaryFileKeychain: @unchecked Sendable {
    let store: SecItemKeychainStore

    private let directory: URL
    private let fileKeychain: FileKeychain

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tandem-app-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("test.keychain-db").path
        let password = UUID().uuidString

        self.directory = directory
        self.fileKeychain = try FileKeychain.createOrOpen(path: path, password: password)
        self.store = SecItemKeychainStore(target: .file(fileKeychain))
    }

    func cleanup() {
        fileKeychain.delete()
        try? FileManager.default.removeItem(at: directory)
    }
}
