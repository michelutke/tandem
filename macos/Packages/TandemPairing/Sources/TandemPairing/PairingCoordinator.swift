import Foundation
import TandemCrypto
import TandemProtocol
import TandemStore
import TandemTransport

/// The Mac's own pairing composition root (E14-09's missing production link): owns the single
/// ``PairingWindow`` a process ever has open, the ``PairingViewModel`` that renders its QR, and --
/// as a ``PairingCandidateDriver`` -- drives one `.pairingCandidate` connection at a time through
/// `docs/protocol/SPEC.md` §2's "Frame order on a pairing-candidate connection" once
/// ``TandemTransport/NWListenerFactory`` hands it off (E12-12's session wiring calls this instead
/// of ever registering a `.pairingCandidate` session -- registration stays `.trusted`-only).
///
/// A single candidate slot ever exists at a time (D-18, ``PairingWindow`` itself enforces this), so
/// this type's own mutable state -- the current candidate's observed phone SPKI DER, read lazily by
/// its ``PairProofVerifier`` exactly like the Mac's own SPKI (E70 rotation) -- never needs to track
/// more than one connection at once either.
public final class PairingCoordinator: PairingCandidateDriver, @unchecked Sendable {
    /// Handed a pairing candidate's confirmation code and its (still unresolved)
    /// ``PairConfirmationViewModel`` once a valid `PairRequest` proof moves the window to
    /// `.confirmationPending` -- e.g. to print the code and/or drive the dialog from a DEBUG
    /// harness hook (E15-22) until the real owner-facing dialog (E14-11) is wired up.
    public typealias ConfirmationPendingHandler = @Sendable (
        _ code: String,
        _ viewModel: PairConfirmationViewModel
    ) -> Void

    public let window: PairingWindow
    public let viewModel: PairingViewModel

    private let macSpkiDerProvider: @Sendable () -> Data
    private let trustStore: TrustStore
    private let dateProvider: DateProvider
    private let onConfirmationPending: ConfirmationPendingHandler?
    private let candidateSpkiDer: CandidateSpkiHolder

    /// - Parameters:
    ///   - fingerprint: The Mac's own identity fingerprint, encoded into every QR this opens.
    ///   - macSpkiDerProvider: The Mac's own certificate SPKI DER, read lazily on every proof/code
    ///     computation (E70 rotation), never captured once.
    public init(
        fingerprint: SpkiFingerprint,
        macSpkiDerProvider: @escaping @Sendable () -> Data,
        secretSource: any SecretSource = SystemSecretSource(),
        addressSource: any LocalAddressSource = GetifaddrsLocalAddressSource(),
        port: Int,
        name: String,
        trustStore: TrustStore,
        dateProvider: @escaping DateProvider,
        onConfirmationPending: ConfirmationPendingHandler? = nil
    ) {
        let candidateSpkiDer = CandidateSpkiHolder()
        let proofVerifier = PairProofVerifier(
            macSpkiDerProvider: macSpkiDerProvider,
            handshakeSpkiDerProvider: { candidateSpkiDer.get() },
            connectionDecisionProvider: { .pairingCandidate }
        )
        let window = PairingWindow(dateProvider: dateProvider, proofVerifier: proofVerifier)
        self.window = window
        self.viewModel = PairingViewModel(
            window: window,
            fingerprint: fingerprint,
            secretSource: secretSource,
            addressSource: addressSource,
            port: port,
            name: name,
            dateProvider: dateProvider
        )
        self.macSpkiDerProvider = macSpkiDerProvider
        self.trustStore = trustStore
        self.dateProvider = dateProvider
        self.onConfirmationPending = onConfirmationPending
        self.candidateSpkiDer = candidateSpkiDer
    }

    public func drive(session: any TandemSession, handshakeSpkiDer: Data) async {
        candidateSpkiDer.set(handshakeSpkiDer)
        defer { candidateSpkiDer.clear() }

        let sink = TandemSessionPairingCandidateSink(session: session)
        let flow = PairingCandidateFlow(window: window, sink: sink)
        guard let challenge = await flow.hellosCompleted() else { return }

        let resolution = ResolutionFlag()
        var pendingConfirmation: PairConfirmationViewModel?
        var confirmationBuilt = false

        let frames = await session.receive(.control)
        for await frame in frames {
            if resolution.isResolved { continue }

            switch frame.payload {
            case .pairRequest(let request)? where !confirmationBuilt:
                await flow.pairRequestReceived(proof: request.proof)
                guard window.isConfirmationPending else { return }
                confirmationBuilt = true
                guard let confirmationViewModel = makeConfirmationViewModel(
                    request: request,
                    challenge: challenge,
                    handshakeSpkiDer: handshakeSpkiDer,
                    sink: sink,
                    resolution: resolution
                ) else {
                    await flow.wrongPayloadReceived()
                    return
                }
                pendingConfirmation = confirmationViewModel
            case .heartbeat?:
                await flow.heartbeatReceived()
                if window.closedReason != nil { return }
            default:
                await flow.wrongPayloadReceived()
                return
            }
        }

        if !resolution.isResolved {
            flow.connectionClosed()
            pendingConfirmation?.connectionDidClose()
        }
    }

    private func makeConfirmationViewModel(
        request: Tandem_V1_PairRequest,
        challenge: Data,
        handshakeSpkiDer: Data,
        sink: any PairingCandidateSink,
        resolution: ResolutionFlag
    ) -> PairConfirmationViewModel? {
        guard let code = try? ConfirmationCode.compute(
            secret: viewModel.currentPayload.secret,
            macSpkiDer: macSpkiDerProvider(),
            phoneSpkiDer: handshakeSpkiDer,
            channelBinding: challenge
        ) else {
            return nil
        }

        let confirmationViewModel = PairConfirmationViewModel(
            displayNameBytes: Data(request.deviceInfo.displayName.utf8),
            modelBytes: Data(request.deviceInfo.model.utf8),
            confirmationCode: code,
            handshakeSpkiDer: handshakeSpkiDer,
            window: window,
            sink: sink,
            trustStore: trustStore,
            dateProvider: dateProvider,
            onResolved: { resolution.resolve() }
        )
        onConfirmationPending?(code, confirmationViewModel)
        return confirmationViewModel
    }
}

/// The real ``PairingCandidateSink``: sends/closes over a live, already-`.ready` ``TandemSession``.
private struct TandemSessionPairingCandidateSink: PairingCandidateSink {
    let session: any TandemSession

    func sendPairChallenge(_ challenge: Data) async throws {
        var message = Tandem_V1_PairChallenge()
        message.challenge = challenge
        try await session.send(.control, payload: .pairChallenge(message))
    }

    func sendPairRejected(_ reason: PairRejectedWireReason) async throws {
        var message = Tandem_V1_PairRejected()
        message.reason = reason.wireReason
        try await session.send(.control, payload: .pairRejected(message))
    }

    func closePairingFailed() async {
        await session.close()
    }

    func sendPairAccepted() async throws {
        try await session.send(.control, payload: .pairAccepted(Tandem_V1_PairAccepted()))
    }
}

private extension PairRejectedWireReason {
    var wireReason: Tandem_V1_PairRejectedReason {
        switch self {
        case .rejectedByOwner: return .rejectedByOwner
        case .pairingUnavailable: return .pairingUnavailable
        }
    }
}

/// Holds the current pairing candidate's observed phone SPKI DER, read lazily by ``PairProofVerifier``
/// (`nil` whenever no candidate is in flight) -- set/cleared by ``PairingCoordinator/drive(session:handshakeSpkiDer:)``
/// around that one candidate's own lifetime.
private final class CandidateSpkiHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Data?

    func set(_ newValue: Data?) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func clear() {
        set(nil)
    }
}

/// Atomic test-and-set flag a candidate's ``PairConfirmationViewModel`` resolution flips exactly
/// once, from whatever task the owner (or a DEBUG auto-confirm hook) resolves it on -- read by
/// ``PairingCoordinator/drive(session:handshakeSpkiDer:)``'s own frame loop, on its own task, so
/// that loop stops driving ``PairingCandidateFlow`` once this candidate's outcome is no longer its
/// concern (mirrors ``PairingCandidateFlow/claimFailure()``'s own idiom).
private final class ResolutionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var resolved = false

    var isResolved: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resolved
    }

    func resolve() {
        lock.lock()
        resolved = true
        lock.unlock()
    }
}
