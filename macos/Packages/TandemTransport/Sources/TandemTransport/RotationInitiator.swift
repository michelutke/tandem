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
/// session's `VersionHello` exchange is complete. At most one `KeyRotation` is sent per session.
actor RotationInitiator {
    private static let logger = Logger(subsystem: "dev.tandem.transport", category: "RotationInitiator")

    private let session: any TandemSession
    private let handshakeFingerprint: SpkiFingerprint
    private let coordinator: RotationCoordinator
    private let trustStore: TrustStore
    private let window: any PairingWindowState
    private let dateProvider: DateProvider
    private var challenge: Data?
    private var sent = false

    init(
        session: any TandemSession,
        handshakeFingerprint: SpkiFingerprint,
        coordinator: RotationCoordinator,
        trustStore: TrustStore,
        window: any PairingWindowState,
        dateProvider: @escaping DateProvider
    ) {
        self.session = session
        self.handshakeFingerprint = handshakeFingerprint
        self.coordinator = coordinator
        self.trustStore = trustStore
        self.window = window
        self.dateProvider = dateProvider
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
            try await session.send(.control, payload: .keyRotation(rotation))
        } catch {
            Self.logger.error("rotation initiate failed")
        }
    }

    func receivedAck() {
        guard sent, let peer = primaryPeer() else { return }
        do {
            try coordinator.recordAck(forRecordId: peer.recordId)
        } catch {
            Self.logger.error("rotation ack handling failed")
        }
    }

    func receivedReject(_ reason: Tandem_V1_RotationRejectReason) {
        Self.logger.error("rotation_initiate_rejected reason=\(reason.rawValue)")
    }

    private func primaryPeer() -> PeerRecord? {
        guard let peer = try? trustStore.authenticatedPeer(handshakeFingerprint, now: dateProvider()),
              peer.pin == .primary else { return nil }
        return peer.record
    }
}
