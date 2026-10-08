import Foundation
import TandemCrypto
import TandemTransport

/// The Mac's side of one candidate's manual-pairing message sequence (`docs/protocol/SPEC.md` §
/// Manual pairing, ADR-008): phone `Commitment`, Mac `Commitment`, phone `Reveal`, Mac `Reveal`.
/// Driven from ``PairingCoordinator``'s frame loop, one message at a time. Every deviation -- a
/// wrong length, a repeated or out-of-order message, a `Reveal` not matching its `Commitment`, any
/// other payload -- fails the candidate through ``PairingCandidateFlow/wrongPayloadReceived()``
/// (`PairRejected(PAIRING_UNAVAILABLE)`, close, one attempt burned), and nothing is pinned here:
/// trust is committed only by the owner's later Pair click. No fingerprint or prefix is compared.
final class ManualPairingHandshake {
    enum Outcome {
        case inProgress
        case failed
        /// Both reveals verified; the 6-digit SAS to show the owner.
        case sasReady(String)
    }

    private enum Step {
        case awaitingPhoneCommitment
        case awaitingPhoneReveal(phoneCommitment: Data, nonceMac: Data)
        case finished
    }

    private let window: PairingWindow
    private let flow: PairingCandidateFlow
    private let sink: any PairingCandidateSink
    private let token: PairingCandidateToken
    private let nonceSource: any ManualNonceSource
    private let context: ManualPairingSas.Context
    private var step = Step.awaitingPhoneCommitment

    init(
        window: PairingWindow,
        flow: PairingCandidateFlow,
        sink: any PairingCandidateSink,
        token: PairingCandidateToken,
        nonceSource: any ManualNonceSource,
        context: ManualPairingSas.Context
    ) {
        self.window = window
        self.flow = flow
        self.sink = sink
        self.token = token
        self.nonceSource = nonceSource
        self.context = context
    }

    func commitmentReceived(_ hash: Data) async -> Outcome {
        guard case .awaitingPhoneCommitment = step,
              hash.count == ManualPairingSas.commitmentByteCount,
              window.manualCommitmentReceived(token)
        else {
            return await fail()
        }
        let nonceMac = nonceSource.generateNonce()
        guard let macCommitment = try? ManualPairingSas.commitment(role: .mac, nonce: nonceMac, context: context),
              (try? await sink.sendCommitment(macCommitment)) != nil else {
            return await fail()
        }
        step = .awaitingPhoneReveal(phoneCommitment: hash, nonceMac: nonceMac)
        return .inProgress
    }

    func revealReceived(_ noncePhone: Data) async -> Outcome {
        guard case .awaitingPhoneReveal(let phoneCommitment, let nonceMac) = step,
              ManualPairingSas.verifyCommitment(
                phoneCommitment,
                role: .phone,
                revealedNonce: noncePhone,
                context: context
              ),
              window.manualRevealVerified(token),
              (try? await sink.sendReveal(nonceMac)) != nil,
              let sas = try? ManualPairingSas.sas(noncePhone: noncePhone, nonceMac: nonceMac, context: context)
        else {
            return await fail()
        }
        step = .finished
        return .sasReady(sas)
    }

    /// Any payload other than the next expected manual message.
    func unexpectedMessageReceived() async -> Outcome {
        await fail()
    }

    private func fail() async -> Outcome {
        step = .finished
        await flow.wrongPayloadReceived()
        return .failed
    }
}
