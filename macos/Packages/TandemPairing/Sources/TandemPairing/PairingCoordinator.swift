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

    let macSpkiDerProvider: @Sendable () -> Data
    private let trustStore: TrustStore
    private let dateProvider: DateProvider
    private let clock: any Clock<Duration>
    private let sessionRegistry: any ControlSessionRegistering
    private let onConfirmationPending: ConfirmationPendingHandler?
    private let onPeerPaired: (@Sendable () -> Void)?
    private let candidateSpkiDer: CandidateSpkiHolder
    let manualNonceSource: any ManualNonceSource

    /// - Parameters:
    ///   - fingerprint: The Mac's own identity fingerprint, encoded into every QR this opens.
    ///   - macSpkiDerProvider: The Mac's own certificate SPKI DER, read lazily on every proof/code
    ///     computation (E70 rotation), never captured once.
    ///   - clock: Drives the active 10 s `PairRequest` deadline (E14-16 finding #5, E00-24 seam
    ///     rule) -- never an unseamed `sleep`.
    ///   - sessionRegistry: Where a candidate that reaches `PairAccepted` is registered as an
    ///     ordinary trusted session (E14-16 finding #6) -- the same instance
    ///     ``TandemTransport/NWListenerFactory`` registers every other trusted session in.
    public init(
        fingerprint: SpkiFingerprint,
        macSpkiDerProvider: @escaping @Sendable () -> Data,
        secretSource: any SecretSource = SystemSecretSource(),
        addressSource: any LocalAddressSource = GetifaddrsLocalAddressSource(),
        port: Int,
        name: String,
        trustStore: TrustStore,
        dateProvider: @escaping DateProvider,
        clock: any Clock<Duration> = ContinuousClock(),
        sessionRegistry: any ControlSessionRegistering,
        regeneratesOnExpiry: Bool = true,
        mode: PairingMode = .qrCode,
        manualNonceSource: any ManualNonceSource = SystemManualNonceSource(),
        onConfirmationPending: ConfirmationPendingHandler? = nil,
        onPeerPaired: (@Sendable () -> Void)? = nil
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
            dateProvider: dateProvider,
            regeneratesOnExpiry: regeneratesOnExpiry
        )
        self.macSpkiDerProvider = macSpkiDerProvider
        self.trustStore = trustStore
        self.dateProvider = dateProvider
        self.clock = clock
        self.sessionRegistry = sessionRegistry
        self.onConfirmationPending = onConfirmationPending
        self.onPeerPaired = onPeerPaired
        self.candidateSpkiDer = candidateSpkiDer
        self.manualNonceSource = manualNonceSource
        if mode == .manual { window.openManual() }
    }

    public func drive(session: any TandemSession, handshakeSpkiDer: Data, token: PairingCandidateToken) async {
        candidateSpkiDer.set(token, handshakeSpkiDer)
        defer { candidateSpkiDer.clear(token) }

        let sink = TandemSessionPairingCandidateSink(session: session)
        let flow = PairingCandidateFlow(window: window, sink: sink, token: token)
        guard let challenge = await flow.hellosCompleted() else {
            // `token` no longer names the current candidate (window regenerated/expired between
            // admission and here) -- this connection was never told anything and must not be left
            // dangling open (E14-16 finding #2).
            await session.close()
            return
        }

        let resolution = ResolutionFlag()
        var pendingConfirmation: PairConfirmationViewModel?
        let registeredFingerprint = FingerprintBox()
        defer {
            if !resolution.isResolved {
                flow.connectionClosed()
                pendingConfirmation?.connectionDidClose()
            }
            if let fingerprint = registeredFingerprint.value {
                let sessionRegistry = sessionRegistry
                Task { await sessionRegistry.removeIfCurrent(fingerprint, session: session) }
            }
        }

        // E14-16 finding #5 (SPEC.md §10 "`PairRequest` deadline"): a candidate that never sends a
        // `PairRequest` at all would otherwise leave this whole frame loop parked on
        // `frames.next()` forever, so this watcher actively closes the connection once the 10 s
        // deadline elapses -- cancelled the moment a `PairRequest` (valid or not) arrives, or this
        // `drive()` call returns for any other reason.
        let deadlineTask = Task { [clock] in
            try? await clock.sleep(for: .seconds(Int(PairingWindow.defaultCandidateRequestDeadline)))
            guard !Task.isCancelled else { return }
            await flow.requestDeadlineElapsed()
        }
        defer { deadlineTask.cancel() }

        let handshake = makeHandshake(
            session: session, flow: flow, token: token, spkiDer: handshakeSpkiDer, challenge: challenge
        )
        let context = PairRequestContext(
            challenge: challenge,
            handshakeSpkiDer: handshakeSpkiDer,
            sink: sink,
            token: token,
            resolution: resolution,
            session: session,
            registeredFingerprint: registeredFingerprint
        )

        let frames = await session.receive(.control)
        pendingConfirmation = await runFrameLoop(
            frames, flow: flow, handshake: handshake, deadlineTask: deadlineTask, context: context
        )
    }

    public func candidateAbandoned(token: PairingCandidateToken) async {
        window.releaseCandidate(token)
    }

    /// `drive()`'s own frame loop, extracted to keep that function's length/complexity down.
    /// Returns the confirmation view model built along the way, if any, so `drive()`'s own `defer`
    /// can still call ``PairConfirmationViewModel/connectionDidClose()`` on it.
    private func runFrameLoop(
        _ frames: InboundFrameStream,
        flow: PairingCandidateFlow,
        handshake: ManualPairingHandshake?,
        deadlineTask: Task<Void, Never>,
        context: PairRequestContext
    ) async -> PairConfirmationViewModel? {
        var pendingConfirmation: PairConfirmationViewModel?
        var confirmationBuilt = false
        for await frame in frames {
            if context.resolution.isResolved { continue }
            let manualActive = handshake != nil && !confirmationBuilt
            let qrActive = handshake == nil && !confirmationBuilt

            switch frame.payload {
            case .commitment? where manualActive, .reveal? where manualActive, .pairRequest? where qrActive:
                deadlineTask.cancel()
                switch await advance(frame.payload, flow: flow, handshake: handshake, context: context) {
                case .inProgress: break
                case .abort: return pendingConfirmation
                case .confirmationPending(let confirmationViewModel):
                    confirmationBuilt = true
                    pendingConfirmation = confirmationViewModel
                }
            case .heartbeat?:
                await flow.heartbeatReceived()
                // Excludes `.paired` (E14-16 finding #4): this exact heartbeat can race this
                // connection's own `pair()` between it committing the window to `.paired` and
                // that same call's still-suspended `PairAccepted` send/registration finishing --
                // returning here in that window would tear this `drive()` call down (and, via its
                // own `defer`, de-register the session `pair()` just registered) out from under a
                // connection that is succeeding, not failing.
                if let reason = window.closedReason, reason != .paired { return pendingConfirmation }
            default:
                await rejectUnexpected(frame.payload, flow: flow, manual: handshake != nil, context: context)
                return pendingConfirmation
            }
        }
        return pendingConfirmation
    }

    /// Everything a `PairRequest` frame's handling needs beyond the request itself, bundled to
    /// keep `handlePairRequest`/`makeConfirmationViewModel`'s own parameter counts down.
    struct PairRequestContext {
        let challenge: Data
        let handshakeSpkiDer: Data
        let sink: any PairingCandidateSink
        let token: PairingCandidateToken
        let resolution: ResolutionFlag
        let session: any TandemSession
        let registeredFingerprint: FingerprintBox
    }

    /// The `.pairRequest` branch of `drive()`'s frame loop, extracted to keep that function's own
    /// length/complexity down. `.abort` means the caller must `return` from `drive()` without
    /// setting `pendingConfirmation`, matching the two `guard ... else { return }`s this replaces.
    func handlePairRequest(
        _ request: Tandem_V1_PairRequest,
        flow: PairingCandidateFlow,
        context: PairRequestContext
    ) async -> CandidateStep {
        await flow.pairRequestReceived(proof: request.proof)
        guard window.isConfirmationPending else { return .abort }
        guard let confirmationViewModel = makeConfirmationViewModel(request: request, context: context) else {
            await flow.wrongPayloadReceived()
            return .abort
        }
        return .confirmationPending(confirmationViewModel)
    }

    private func makeConfirmationViewModel(
        request: Tandem_V1_PairRequest,
        context: PairRequestContext
    ) -> PairConfirmationViewModel? {
        guard let code = try? ConfirmationCode.compute(
            secret: viewModel.currentPayload.secret,
            macSpkiDer: macSpkiDerProvider(),
            phoneSpkiDer: context.handshakeSpkiDer,
            channelBinding: context.challenge
        ) else {
            return nil
        }
        return buildConfirmationViewModel(
            code: code,
            displayNameBytes: Data(request.deviceInfo.displayName.utf8),
            modelBytes: Data(request.deviceInfo.model.utf8),
            acceptance: .qrCode,
            context: context
        )
    }

    func buildConfirmationViewModel(
        code: String,
        displayNameBytes: Data,
        modelBytes: Data,
        acceptance: PairAcceptance,
        context: PairRequestContext
    ) -> PairConfirmationViewModel {
        let confirmationViewModel = PairConfirmationViewModel(
            displayNameBytes: displayNameBytes,
            modelBytes: modelBytes,
            confirmationCode: code,
            handshakeSpkiDer: context.handshakeSpkiDer,
            window: window,
            token: context.token,
            sink: context.sink,
            trustStore: trustStore,
            dateProvider: dateProvider,
            onResolved: { context.resolution.resolve() },
            onPaired: { [sessionRegistry, context, onPeerPaired] in
                guard let fingerprint = try? SpkiFingerprint.of(spkiDer: context.handshakeSpkiDer) else { return }
                context.registeredFingerprint.set(fingerprint)
                await sessionRegistry.register(fingerprint, session: context.session)
                // No SessionServiceHost attaches to a pairing-registered session, so end the
                // control-channel replay window here or held frames would accumulate for its lifetime.
                await context.session.sealSetup()
                onPeerPaired?()
            },
            acceptance: acceptance
        )
        onConfirmationPending?(code, confirmationViewModel)
        return confirmationViewModel
    }
}

/// The real ``PairingCandidateSink``: sends/closes over a live, already-`.ready` ``TandemSession``.
struct TandemSessionPairingCandidateSink: PairingCandidateSink {
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

    func sendCommitment(_ hash: Data) async throws {
        var message = Tandem_V1_Commitment()
        message.hash = hash
        try await session.send(.control, payload: .commitment(message))
    }

    func sendReveal(_ nonce: Data) async throws {
        var message = Tandem_V1_Reveal()
        message.nonce = nonce
        try await session.send(.control, payload: .reveal(message))
    }

    func sendManualPairResult() async throws {
        var message = Tandem_V1_ManualPairResult()
        message.accepted = true
        try await session.send(.control, payload: .manualPairResult(message))
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
