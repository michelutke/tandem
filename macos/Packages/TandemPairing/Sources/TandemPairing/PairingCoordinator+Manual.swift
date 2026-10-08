import Foundation
import TandemCrypto
import TandemProtocol
import TandemTransport

/// The manual-pairing branch of ``PairingCoordinator``'s candidate frame loop (E73-04, ADR-008).
extension PairingCoordinator {
    enum CandidateStep {
        case inProgress
        case abort
        case confirmationPending(PairConfirmationViewModel)
    }

    /// Routes one frame of the active sequence (`PairRequest` for a QR window, `Commitment`/`Reveal`
    /// for a manual one) and reports how the candidate moved.
    func advance(
        _ payload: Tandem_V1_Envelope.OneOf_Payload?,
        flow: PairingCandidateFlow,
        handshake: ManualPairingHandshake?,
        context: PairRequestContext
    ) async -> CandidateStep {
        if let handshake {
            return await manualStep(payload, handshake: handshake, context: context)
        }
        guard case .pairRequest(let request)? = payload else { return .abort }
        return await handlePairRequest(request, flow: flow, context: context)
    }

    /// Any payload outside the active sequence ends the candidate. On a manual window a `Revoke` is
    /// the phone reporting a code mismatch, which closes the whole window like an owner decline
    /// (ADR-008 step 6, D-16); everything else burns one attempt.
    func rejectUnexpected(
        _ payload: Tandem_V1_Envelope.OneOf_Payload?,
        flow: PairingCandidateFlow,
        manual: Bool,
        context: PairRequestContext
    ) async {
        if manual, case .revoke? = payload, window.manualMismatchReported(context.token) {
            await context.sink.closePairingFailed()
            return
        }
        await flow.wrongPayloadReceived()
    }

    /// `nil` unless the window was opened in manual mode: only then does a candidate speak the
    /// commit-then-reveal sequence instead of `PairRequest`.
    func makeHandshake(
        session: any TandemSession,
        flow: PairingCandidateFlow,
        token: PairingCandidateToken,
        spkiDer: Data,
        challenge: Data
    ) -> ManualPairingHandshake? {
        guard window.mode == .manual else { return nil }
        return ManualPairingHandshake(
            window: window,
            flow: flow,
            sink: TandemSessionPairingCandidateSink(session: session),
            token: token,
            nonceSource: manualNonceSource,
            context: ManualPairingSas.Context(
                macSpkiDer: macSpkiDerProvider(),
                phoneSpkiDer: spkiDer,
                channelBinding: challenge
            )
        )
    }

    /// Feeds one `Commitment`/`Reveal` frame to `handshake`. The manual flow carries no
    /// `DeviceInfo` (SPEC § Manual pairing), so the dialog and the pinned record use a fixed
    /// placeholder name rather than anything the unauthenticated peer could supply.
    func manualStep(
        _ payload: Tandem_V1_Envelope.OneOf_Payload?,
        handshake: ManualPairingHandshake,
        context: PairRequestContext
    ) async -> CandidateStep {
        let outcome: ManualPairingHandshake.Outcome
        switch payload {
        case .commitment(let message)?: outcome = await handshake.commitmentReceived(message.hash)
        case .reveal(let message)?: outcome = await handshake.revealReceived(message.nonce)
        default: outcome = await handshake.unexpectedMessageReceived()
        }
        switch outcome {
        case .inProgress: return .inProgress
        case .failed: return .abort
        case .sasReady(let sas):
            return .confirmationPending(buildConfirmationViewModel(
                code: sas,
                displayNameBytes: Data("Phone".utf8),
                modelBytes: Data("New phone".utf8),
                acceptance: .manual,
                context: context
            ))
        }
    }
}
