import Foundation
import os
import TandemCrypto
import TandemProtocol
import TandemStore

/// What ``RotationReceiver`` needs beyond the trust store: the pairing window (a rotation is
/// refused while one is open), the injected wall clock (E00-24) for grace-pin lifetimes, and the
/// CSPRNG seam for the per-session `RotationChallenge`.
public struct RotationReceiverConfiguration: Sendable {
    public let window: any PairingWindowState
    public let dateProvider: DateProvider
    public let challengeSource: @Sendable () -> Data
    public let onRejected: @Sendable (Tandem_V1_RotationRejectReason) -> Void

    public init(
        window: any PairingWindowState,
        dateProvider: @escaping DateProvider,
        challengeSource: @escaping @Sendable () -> Data = RotationReceiverConfiguration.systemChallenge,
        onRejected: @escaping @Sendable (Tandem_V1_RotationRejectReason) -> Void =
            RotationReceiverConfiguration.logRejection
    ) {
        self.window = window
        self.dateProvider = dateProvider
        self.challengeSource = challengeSource
        self.onRejected = onRejected
    }
}

/// Mac side of key rotation for one Ready control session (E70-05, SPEC.md #key-rotation, D-74):
/// sends this session's one `RotationChallenge`, then answers the first `KeyRotation` through the
/// ordered receiver algorithm. A rotation only ever touches the record of the peer authenticated
/// by this session's TLS handshake. A reject leaves the trust store unchanged and the connection
/// open. Frames arrive serially from the session's single `CONTROL` reader, so no two
/// `KeyRotation`s are ever evaluated concurrently.
actor RotationReceiver {
    private static let logger = Logger(subsystem: "dev.tandem.transport", category: "RotationReceiver")

    private let session: any TandemSession
    private let handshakeFingerprint: SpkiFingerprint
    private let handshakeSpkiDer: Data
    private let trustStore: TrustStore
    private let configuration: RotationReceiverConfiguration
    private var challenge: Data?

    init(
        session: any TandemSession,
        handshakeFingerprint: SpkiFingerprint,
        handshakeSpkiDer: Data,
        trustStore: TrustStore,
        configuration: RotationReceiverConfiguration
    ) {
        self.session = session
        self.handshakeFingerprint = handshakeFingerprint
        self.handshakeSpkiDer = handshakeSpkiDer
        self.trustStore = trustStore
        self.configuration = configuration
    }

    func sendChallenge() async {
        let value = configuration.challengeSource()
        challenge = value
        var message = Tandem_V1_RotationChallenge()
        message.challenge = value
        await send(.rotationChallenge(message))
    }

    func handle(_ message: Tandem_V1_KeyRotation) async {
        if let reason = evaluate(message) {
            configuration.onRejected(reason)
            var reject = Tandem_V1_RotationReject()
            reject.reason = reason
            await send(.rotationReject(reject))
        } else {
            await send(.rotationAck(Tandem_V1_RotationAck()))
        }
    }

    /// The SPEC's ordered receiver algorithm; `nil` means acknowledge.
    private func evaluate(_ message: Tandem_V1_KeyRotation) -> Tandem_V1_RotationRejectReason? {
        let now = configuration.dateProvider()
        let peer: AuthenticatedPeer
        do {
            guard let found = try trustStore.authenticatedPeer(handshakeFingerprint, now: now) else {
                return .unauthenticatedSession
            }
            peer = found
        } catch {
            Self.logger.error("rotation trust store read failed")
            return .rotationUnavailable
        }
        let newFingerprint = try? SpkiFingerprint.of(spkiDer: message.newSpkiDer)
        if let newFingerprint, peer.record.fingerprint.matches(newFingerprint) { return nil }
        guard peer.pin == .primary else { return .notPrimaryPin }
        guard !configuration.window.isOpen else { return .rotationUnavailable }
        guard let newFingerprint else { return .invalidSignature }
        guard verifiesAgainstChallenge(message) else { return .invalidSignature }
        return pin(newFingerprint, replacing: peer.record, now: now)
    }

    private func verifiesAgainstChallenge(_ message: Tandem_V1_KeyRotation) -> Bool {
        guard let sessionChallenge = challenge else { return false }
        challenge = nil
        return RotationVerifier.verify(
            oldSpkiDer: handshakeSpkiDer,
            newSpkiDer: message.newSpkiDer,
            challenge: sessionChallenge,
            sigOldKey: message.sigOldKey,
            sigNewKey: message.sigNewKey
        )
    }

    private func pin(
        _ newFingerprint: SpkiFingerprint,
        replacing record: PeerRecord,
        now: Date
    ) -> Tandem_V1_RotationRejectReason? {
        do {
            guard try !trustStore.holdsPin(newFingerprint) else { return .duplicateKey }
            try trustStore.rotatePrimary(of: record, to: newFingerprint, now: now)
            return nil
        } catch {
            Self.logger.error("rotation pin swap failed")
            return .rotationUnavailable
        }
    }

    private func send(_ payload: Tandem_V1_Envelope.OneOf_Payload) async {
        do {
            try await session.send(.control, payload: payload)
        } catch {
            Self.logger.error("rotation reply send failed")
        }
    }
}

extension RotationReceiverConfiguration {
    private static let logger = Logger(subsystem: "dev.tandem.transport", category: "RotationReceiver")

    @Sendable
    public static func systemChallenge() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<RotationVerifier.challengeByteCount).map { _ in
            UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        })
    }

    /// One event per rejection carrying the reason only -- never an SPKI or signature byte.
    @Sendable
    public static func logRejection(_ reason: Tandem_V1_RotationRejectReason) {
        switch reason {
        case .invalidSignature: logger.error("rotation_rejected reason=INVALID_SIGNATURE")
        case .unauthenticatedSession: logger.error("rotation_rejected reason=UNAUTHENTICATED_SESSION")
        case .notPrimaryPin: logger.error("rotation_rejected reason=NOT_PRIMARY_PIN")
        case .duplicateKey: logger.error("rotation_rejected reason=DUPLICATE_KEY")
        case .rotationUnavailable: logger.error("rotation_rejected reason=ROTATION_UNAVAILABLE")
        case .unspecified, .UNRECOGNIZED: logger.error("rotation_rejected reason=UNSPECIFIED")
        }
    }
}

/// Grace-pin upkeep around a trusted session's lifetime (SPEC.md #key-rotation "Grace pin"): a
/// session authenticated with the new key completing `VersionHello` purges the old pin, as does
/// the grace session closing; pins past their 7-day lifetime are purged on every Ready.
struct GracePinMaintenance: Sendable {
    private static let logger = Logger(subsystem: "dev.tandem.transport", category: "GracePinMaintenance")

    let trustStore: TrustStore
    let dateProvider: DateProvider

    func admit(_ fingerprint: SpkiFingerprint) -> Bool? {
        do {
            guard let peer = try trustStore.authenticatedPeer(fingerprint, now: dateProvider()) else { return nil }
            switch peer.pin {
            case .primary: return false
            case .grace: return try trustStore.claimGracePin(fingerprint) ? true : nil
            }
        } catch {
            Self.logger.error("grace pin admission failed")
            return nil
        }
    }

    func sessionReady(authenticatedBy fingerprint: SpkiFingerprint) {
        do {
            try trustStore.purgeExpiredGracePins(now: dateProvider())
            try trustStore.purgeGracePin(authenticatedByPrimary: fingerprint)
        } catch {
            Self.logger.error("grace pin purge on ready failed")
        }
    }

    func sessionClosed(authenticatedBy fingerprint: SpkiFingerprint) {
        do {
            try trustStore.purgeGracePin(authenticatedByGrace: fingerprint)
        } catch {
            Self.logger.error("grace pin purge on close failed")
        }
    }
}
