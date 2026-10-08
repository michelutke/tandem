import CryptoKit
import Foundation
import Testing
import TandemCrypto
import TandemStore
@testable import TandemTestSupport
import TandemTransport
@testable import TandemPairing
@testable import TandemProtocol

/// Test fixture and polling helpers for `PairingCoordinatorTests`, split out to keep that file
/// within the file/type-length lint bounds.
extension PairingCoordinatorTests {

    struct Fixture {
        let coordinator: PairingCoordinator
        let window: PairingWindow
        let token: PairingCandidateToken
        let macSpkiDer: Data
        let phoneSpkiDer: Data
        let trustStore: TrustStore
        let sessionRegistry: SpyControlSessionRegistry
        let clock: ManualTestClock
        /// Per-fixture, never shared across tests -- `Testing` runs `@Suite` tests concurrently by
        /// default, so a `static` box here would let one test observe (or overwrite) another's
        /// `onConfirmationPending` callback.
        let confirmationBox: ConfirmationBox

        static func make(mode: PairingMode = .qrCode) throws -> Fixture {
            let clock = ManualTestClock()
            let macSpkiDer = Self.makeValidSpkiDer()
            let phoneSpkiDer = Self.makeValidSpkiDer()
            let fingerprint = try SpkiFingerprint.of(spkiDer: macSpkiDer)
            let trustStore = TrustStore(keychainStore: InMemoryKeychainStore())
            let sessionRegistry = SpyControlSessionRegistry()
            let confirmationBox = ConfirmationBox()

            let coordinator = PairingCoordinator(
                fingerprint: fingerprint,
                macSpkiDerProvider: { macSpkiDer },
                port: 54321,
                name: "Test Mac",
                trustStore: trustStore,
                dateProvider: FixedDateProvider(clock: clock).provider,
                clock: clock,
                sessionRegistry: sessionRegistry,
                mode: mode,
                onConfirmationPending: { _, viewModel in
                    confirmationBox.set(viewModel)
                }
            )
            let token = try #require(coordinator.window.admitCandidate())

            return Fixture(
                coordinator: coordinator,
                window: coordinator.window,
                token: token,
                macSpkiDer: macSpkiDer,
                phoneSpkiDer: phoneSpkiDer,
                trustStore: trustStore,
                sessionRegistry: sessionRegistry,
                clock: clock,
                confirmationBox: confirmationBox
            )
        }

        /// A real, structurally valid uncompressed P-256 SPKI DER (matching
        /// `PeerAuthorizerTests.makeValidSpkiDer()`'s construction).
        static func makeValidSpkiDer() -> Data {
            let header = Data([
                0x30, 0x59, 0x30, 0x13,
                0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
                0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07,
                0x03, 0x42, 0x00
            ])
            let point = P256.Signing.PrivateKey().publicKey.x963Representation
            return header + point
        }
    }

    static let pairingUnavailable = Tandem_V1_PairRejected.with { $0.reason = .pairingUnavailable }

    static func pairRequestFrame(proof: Data) -> InboundFrame {
        let request = Tandem_V1_PairRequest.with {
            $0.deviceInfo = Tandem_V1_DeviceInfo.with {
                $0.displayName = "Test Phone"
                $0.model = "Test Model"
            }
            $0.proof = proof
        }
        return InboundFrame(channel: .control, seq: 2, ack: 0, payload: .pairRequest(request))
    }

    static func waitForChallenge(_ session: FakeTandemSession, timeout: TimeInterval) async throws -> Data {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while ContinuousClock.now < deadline {
            let sent = await session.sent
            for frame in sent {
                if case .pairChallenge(let message) = frame.payload {
                    return message.challenge
                }
            }
            try? await ContinuousClock().sleep(for: .milliseconds(5))
        }
        struct TimedOut: Error {}
        throw TimedOut()
    }

    static func waitForConfirmation(
        _ fixture: Fixture, timeout: TimeInterval
    ) async throws -> PairConfirmationViewModel {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while ContinuousClock.now < deadline {
            if let viewModel = fixture.confirmationBox.value {
                return viewModel
            }
            try? await ContinuousClock().sleep(for: .milliseconds(5))
        }
        struct TimedOut: Error {}
        throw TimedOut()
    }

    static func waitFor(timeout: TimeInterval, _ condition: @Sendable () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while ContinuousClock.now < deadline {
            if await condition() {
                return true
            }
            try? await ContinuousClock().sleep(for: .milliseconds(5))
        }
        return false
    }
}

/// Lock-protected single-slot box for the one ``PairConfirmationViewModel`` a test's
/// `onConfirmationPending` hook ever receives.
final class ConfirmationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: PairConfirmationViewModel?

    var value: PairConfirmationViewModel? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ viewModel: PairConfirmationViewModel) {
        lock.lock()
        stored = viewModel
        lock.unlock()
    }
}

/// ``ControlSessionRegistering`` spy: records every currently-registered fingerprint, mirroring
/// `TandemTransportTests`' own private copy (not visible from this package's test target).
final class SpyControlSessionRegistry: ControlSessionRegistering, @unchecked Sendable {
    private let lock = NSLock()
    private var fingerprints: Set<SpkiFingerprint> = []

    var registeredFingerprints: Set<SpkiFingerprint> {
        lock.lock()
        defer { lock.unlock() }
        return fingerprints
    }

    func register(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async {
        insert(spkiFingerprint)
    }

    func removeIfCurrent(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async {
        remove(spkiFingerprint)
    }

    private func insert(_ spkiFingerprint: SpkiFingerprint) {
        lock.lock()
        fingerprints.insert(spkiFingerprint)
        lock.unlock()
    }

    private func remove(_ spkiFingerprint: SpkiFingerprint) {
        lock.lock()
        fingerprints.remove(spkiFingerprint)
        lock.unlock()
    }
}
