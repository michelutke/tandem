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
/// `NWListenerFactory`'s `onSessionRegistered`/`onSessionEnded` seams. Both only enqueue: one
/// consumer applies the events strictly in arrival order, finishing each attach or detach before
/// the next event, so an end that arrives while a session is attaching detaches it afterwards
/// instead of racing it.
public actor SessionServiceHost {
    private enum Event {
        case registered(peer: SpkiFingerprint, session: any TandemSession)
        case ended(peer: SpkiFingerprint, session: any TandemSession)
        case barrier(CheckedContinuation<Void, Never>)
    }

    private struct Attachment {
        let session: any TandemSession
    }

    private let services: [any SessionService]
    private let events: AsyncStream<Event>.Continuation
    private var attachments: [SpkiFingerprint: Attachment] = [:]

    public init(services: [any SessionService]) {
        self.services = services
        let (stream, continuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .unbounded)
        events = continuation
        Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    deinit {
        events.finish()
    }

    /// Queues attaching every service to `session`. A repeat for the session already attached is a
    /// no-op; a different session for the same peer detaches the previous attachment first.
    public nonisolated func sessionRegistered(peer: SpkiFingerprint, session: any TandemSession) {
        events.yield(.registered(peer: peer, session: session))
    }

    /// Queues detaching every service if `session` is still the one attached for `peer`; a stale
    /// end notification for a session already replaced is ignored.
    public nonisolated func sessionEnded(peer: SpkiFingerprint, session: any TandemSession) {
        events.yield(.ended(peer: peer, session: session))
    }

    /// Suspends until every event queued before this call has been applied.
    public func waitUntilIdle() async {
        await withCheckedContinuation { events.yield(.barrier($0)) }
    }

    private func handle(_ event: Event) async {
        switch event {
        case .registered(let peer, let session):
            await attach(peer: peer, session: session)
        case .ended(let peer, let session):
            guard let current = attachments[peer], current.session === session else { return }
            await detachAll(peer: peer)
        case .barrier(let continuation):
            continuation.resume()
        }
    }

    private func attach(peer: SpkiFingerprint, session: any TandemSession) async {
        if let current = attachments[peer] {
            guard !(current.session === session) else { return }
            await detachAll(peer: peer)
        }
        attachments[peer] = Attachment(session: session)
        for service in services {
            await service.attach(peer: peer, session: session)
        }
        await session.sealSetup()
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
