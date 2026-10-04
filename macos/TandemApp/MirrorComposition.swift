import FeatureMirror
import Foundation
import TandemCrypto
import TandemProtocol
import TandemTransport

/// Wires the mirror feature into the app (E62-12): the media acceptor the listener hands first-frame
/// non-`Envelope` connections to, the per-control-session service that issues tickets, the mirror
/// window, and the Mirror quick action's view model. Media is bound only for the control peer's SPKI
/// (invariant 3) and ends, closing the window, with its control session; nothing is logged.
@MainActor
final class MirrorComposition {
    nonisolated let acceptor: MediaConnectionAcceptor
    nonisolated let service: MirrorSessionService<ContinuousClock>
    private let coordinator: MirrorMediaCoordinator
    private var requestModel: MirrorRequestViewModel?
    fileprivate private(set) var currentSession: (any TandemSession)?

    nonisolated init() {
        let clock = ContinuousClock()
        let table = MediaTicketTable(clock: clock)
        let issuer = MediaTicketIssuer(table: table, source: SystemMediaTicketSource(), dateProvider: { Date() })
        let holder = SessionChangeHolder()
        let coordinator = MirrorMediaCoordinator(
            presenter: MirrorWindowPresenter(),
            inputSession: { holder.composition?.currentSession }
        )
        let registry = MediaSessionRegistry(issuer: issuer, onEnded: { id in
            Task { @MainActor in coordinator.sessionEnded(id) }
        })
        self.coordinator = coordinator
        acceptor = MediaConnectionAcceptor(
            validator: MediaTicketValidatorAdapter(validator: MediaTicketValidator(table: table)),
            clock: clock,
            onBound: { binding in
                let id = MediaSessionID(rawValue: binding.sessionID)
                Task {
                    guard await registry.bind(
                        binding.connection, to: id, mirrorSessionId: binding.mirrorSessionId, presentedBy: binding.peer
                    ) else { return }
                    await coordinator.mediaBound(
                        binding.connection, sessionID: id, mirrorSessionId: binding.mirrorSessionId
                    )
                }
            }
        )
        service = MirrorSessionService(
            registry: registry,
            onSessionAttached: { session in holder.attached(session) },
            onSessionDetached: { holder.detached() }
        )
        holder.composition = self
    }

    /// Puts `model` on the current control session now and on every later one.
    func bind(_ model: MirrorRequestViewModel) {
        requestModel = model
        let session = currentSession
        Task { await model.sessionChanged(session) }
    }

    fileprivate func sessionChanged(_ session: (any TandemSession)?) {
        currentSession = session
        guard let requestModel else { return }
        Task { await requestModel.sessionChanged(session) }
    }
}

private final class SessionChangeHolder: @unchecked Sendable {
    weak var composition: MirrorComposition?

    func attached(_ session: any TandemSession) {
        Task { @MainActor [composition] in composition?.sessionChanged(session) }
    }

    func detached() {
        Task { @MainActor [composition] in composition?.sessionChanged(nil) }
    }
}
