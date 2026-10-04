import Foundation
import os
import TandemCrypto
import TandemProtocol
import TandemStore

/// Mac side of a Mac-initiated key rotation for one Ready control session (E70-03, SPEC.md
/// #key-rotation, D-74). Holds the `RotationChallenge` the phone sent unsolicited on this session as
/// `cb`, and writes the signed `KeyRotation` only when the session's peer is authenticated by its
/// primary pin and no pairing window is open. The caller feeds it the session's `CONTROL`
/// `RotationChallenge`, `RotationAck` and `RotationReject` frames and only creates it once the
/// session's `VersionHello` exchange is complete. At most one `KeyRotation` is sent per session; an
/// ack later than ``ackDeadline`` after it is a failed attempt for that session (the old key stays
/// active and the rotation is offered again on the next session).
actor RotationInitiator {
    static let ackDeadline = Duration.seconds(30)
    private static let logger = Logger(subsystem: "dev.tandem.transport", category: "RotationInitiator")

    private let session: any TandemSession
    private let handshakeFingerprint: SpkiFingerprint
    private let coordinator: RotationCoordinator
    private let trustStore: TrustStore
    private let window: any PairingWindowState
    private let dateProvider: DateProvider
    private let clock: any Clock<Duration>
    private var challenge: Data?
    private var sent = false
    private var ackExpired = false
    private var deadlineTask: Task<Void, Never>?

    init(
        session: any TandemSession,
        handshakeFingerprint: SpkiFingerprint,
        coordinator: RotationCoordinator,
        trustStore: TrustStore,
        window: any PairingWindowState,
        dateProvider: @escaping DateProvider,
        clock: any Clock<Duration>
    ) {
        self.session = session
        self.handshakeFingerprint = handshakeFingerprint
        self.coordinator = coordinator
        self.trustStore = trustStore
        self.window = window
        self.dateProvider = dateProvider
        self.clock = clock
    }

    func receivedChallenge(_ value: Data) async {
        guard value.count == RotationVerifier.challengeByteCount else { return }
        challenge = value
        await sendIfPending()
    }

    /// Sends the `KeyRotation` if a rotation is pending for this session's peer; call again after
    /// `RotationCoordinator.begin()` for sessions that were already connected.
    func sendIfPending() async {
        guard !sent, let challenge, !window.isOpen, let peer = primaryPeer() else { return }
        do {
            guard let rotation = try coordinator.keyRotation(forRecordId: peer.recordId, challenge: challenge) else {
                return
            }
            sent = true
            startAckDeadline()
            try await session.send(.control, payload: .keyRotation(rotation))
        } catch {
            Self.logger.error("rotation initiate failed")
        }
    }

    func receivedAck() {
        guard sent, !ackExpired, let peer = primaryPeer() else { return }
        deadlineTask?.cancel()
        do {
            try coordinator.recordAck(forRecordId: peer.recordId)
        } catch {
            Self.logger.error("rotation ack handling failed")
        }
    }

    func receivedReject(_ reason: Tandem_V1_RotationRejectReason) {
        Self.logger.error("rotation_initiate_rejected reason=\(reason.rawValue)")
        guard sent, !ackExpired, primaryPeer() != nil else { return }
        deadlineTask?.cancel()
        do {
            try coordinator.cancel()
        } catch RotationCoordinatorError.alreadyCommitted, RotationCoordinatorError.notInProgress {
            return
        } catch {
            Self.logger.error("rotation reject handling failed")
        }
    }

    private func startAckDeadline() {
        let clock = clock
        deadlineTask = Task { [weak self] in
            try? await clock.sleep(for: Self.ackDeadline)
            guard !Task.isCancelled else { return }
            await self?.expireAck()
        }
    }

    private func expireAck() {
        ackExpired = true
        Self.logger.error("rotation ack timed out")
    }

    private func primaryPeer() -> PeerRecord? {
        guard let peer = try? trustStore.authenticatedPeer(handshakeFingerprint, now: dateProvider()),
              peer.pin == .primary else { return nil }
        return peer.record
    }
}
