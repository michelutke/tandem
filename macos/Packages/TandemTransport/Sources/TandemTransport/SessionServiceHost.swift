import TandemCrypto
import TandemProtocol

/// A feature that runs for the lifetime of one registered session (E22-12): started by
/// ``attach(peer:session:)``, stopped by ``detach(peer:)``. Channel readers must be started from
/// ``attach(peer:session:)`` through ``TandemSession/receive(_:)`` -- the one per-channel dispatch
/// point -- never from a second, independent subscription.
public protocol SessionService: Sendable {
    func attach(peer: SpkiFingerprint, session: any TandemSession) async
    func detach(peer: SpkiFingerprint) async
}

/// Attaches every ``SessionService`` exactly once to a registered session and detaches them when
/// that session ends or is replaced by a newer one for the same peer. The composition root calls
/// ``sessionRegistered(peer:session:)`` and ``sessionEnded(peer:session:)`` from
/// `NWListenerFactory`'s `onSessionRegistered`/`onSessionEnded` seams.
public actor SessionServiceHost {
    private struct Attachment {
        let session: any TandemSession
    }

    private let services: [any SessionService]
    private var attachments: [SpkiFingerprint: Attachment] = [:]

    public init(services: [any SessionService]) {
        self.services = services
    }

    /// Attaches every service to `session`. A repeat call for the session already attached is a
    /// no-op; a different session for the same peer detaches the previous attachment first.
    public func sessionRegistered(peer: SpkiFingerprint, session: any TandemSession) async {
        if let current = attachments[peer] {
            guard !(current.session === session) else { return }
            await detachAll(peer: peer)
        }
        attachments[peer] = Attachment(session: session)
        for service in services {
            await service.attach(peer: peer, session: session)
        }
    }

    /// Detaches every service if `session` is still the one attached for `peer`; a stale end
    /// notification for a session already replaced is ignored.
    public func sessionEnded(peer: SpkiFingerprint, session: any TandemSession) async {
        guard let current = attachments[peer], current.session === session else { return }
        await detachAll(peer: peer)
    }

    private func detachAll(peer: SpkiFingerprint) async {
        attachments[peer] = nil
        for service in services {
            await service.detach(peer: peer)
        }
    }
}

private func === (lhs: any TandemSession, rhs: any TandemSession) -> Bool {
    (lhs as AnyObject) === (rhs as AnyObject)
}
