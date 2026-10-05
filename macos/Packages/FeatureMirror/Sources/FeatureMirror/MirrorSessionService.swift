import Foundation
import Synchronization
import TandemCrypto
import TandemProtocol
import TandemTransport

/// Registers each control session with the ``MediaSessionRegistry`` and answers its
/// `RequestMediaTicket` with a `MediaTicketGrant` (E62-12). The registry's end-of-session signal is
/// the session's own `CONTROL` stream finishing, a source dedicated to this service:
/// ``TandemSession/state`` is unicast and already consumed elsewhere.
public final class MirrorSessionService<C: Clock<Duration> & Sendable>: SessionService, Sendable {
    private struct Active {
        let id: MediaSessionID
        let reader: Task<Void, Never>
    }

    private let registry: MediaSessionRegistry<C>
    private let onSessionAttached: @Sendable (MediaSessionID, any TandemSession) -> Void
    private let onSessionDetached: @Sendable (MediaSessionID) -> Void
    private let active = Mutex<[SpkiFingerprint: Active]>([:])

    public init(
        registry: MediaSessionRegistry<C>,
        onSessionAttached: @escaping @Sendable (MediaSessionID, any TandemSession) -> Void = { _, _ in },
        onSessionDetached: @escaping @Sendable (MediaSessionID) -> Void = { _ in }
    ) {
        self.registry = registry
        self.onSessionAttached = onSessionAttached
        self.onSessionDetached = onSessionDetached
    }

    public func attach(peer: SpkiFingerprint, session: any TandemSession) async {
        let id = MediaSessionID(rawValue: UUID())
        let frames = await session.receive(.control)
        let (states, ended) = AsyncStream<ConnectionStateMachine.ConnectionState>.makeStream()
        await registry.register(states: states, id: id, peer: peer)
        let registry = registry
        let reader = Task {
            for await frame in frames {
                guard case .requestMediaTicket? = frame.payload,
                      let issued = await registry.requestTicket(for: id) else { continue }
                var grant = Tandem_V1_MediaTicketGrant()
                grant.ticket = issued.ticket
                grant.expiresAt = issued.expiresAtMillis
                try? await session.send(.control, payload: .mediaTicketGrant(grant))
            }
            ended.yield(.dead)
            ended.finish()
        }
        active.withLock { $0[peer] = Active(id: id, reader: reader) }
        onSessionAttached(id, session)
    }

    public func detach(peer: SpkiFingerprint) async {
        guard let current = active.withLock({ $0.removeValue(forKey: peer) }) else { return }
        current.reader.cancel()
        await registry.unregister(current.id)
        onSessionDetached(current.id)
    }
}
