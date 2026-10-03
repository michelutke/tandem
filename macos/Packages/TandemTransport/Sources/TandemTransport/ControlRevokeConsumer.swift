import TandemCrypto
import TandemProtocol
import TandemStore

/// Spawned once a `.trusted` session is registered (E14-26, ``NWListenerFactory``'s own
/// `wireSession(adapter:metadataIdentifier:)`): reads `session`'s own `CONTROL` channel
/// (``HeartbeatController``'s own kdoc already reserves this exact stream for "a future `CONTROL`
/// reader" -- this is it) until either a `Revoke` frame arrives, dispatched to
/// ``TandemStore/RevokeHandler`` (a `KeyRotation` frame goes to `rotation`, E70-05, which also
/// sends this session's `RotationChallenge` before the first read), or the stream finishes on its
/// own once `session` closes for any other reason (``TandemSession/receive(_:)``'s own contract). A
/// no-op task if `trustStore` is `nil`. Every other `CONTROL` payload (`Heartbeat` included, already handled by
/// ``HeartbeatController`` off the non-consuming `received` broadcast) is ignored here and the
/// loop keeps reading.
///
/// A free function, not a method on ``NWListenerFactory``, purely so this file (kept small for
/// this repo's `file_length`/`type_body_length` SwiftLint budgets) can build its own adapters
/// without needing cross-file access to that type's own `private` stored properties -- every
/// dependency it needs is passed in explicitly.
///
/// The returned ``Task`` is a thin proxy over an inner, never-cancelled `worker` task that does
/// the actual reading and dispatching (E14-27 HIGH fix). `AsyncStream`'s `next()` can return `nil`
/// once its consuming task is cancelled even when a value (here, a `Revoke` frame) was already
/// buffered -- `RevokeHandler.handle`'s own `for await state in session.state.prefix(1)` has the
/// identical hazard. Unlike ``HeartbeatController``'s observer loops (dropping one reset there is
/// harmless: the next send/receive re-arms the same timer), losing a dequeued-but-uncommitted
/// `Revoke` here would silently leave a revoked peer's trust record intact (AC-09/AC-12), so this
/// consumer cannot tolerate that race at all. Cancelling the returned proxy (the caller's only
/// handle) therefore never reaches `worker`, so a `Revoke` frame that has already arrived on the
/// wire is always fully handled, no matter when or whether the caller cancels.
func startControlRevokeReader(
    fingerprint: SpkiFingerprint,
    session: ByteStreamSession,
    sessionRegistry: any ControlSessionRegistering,
    trustStore: TrustStore?,
    rotation: RotationReceiver? = nil
) -> Task<Void, Never>? {
    guard let trustStore else { return nil }
    let worker = Task {
        let frames = await session.receive(.control)
        await rotation?.sendChallenge()
        for await frame in frames {
            switch frame.payload {
            case .revoke?:
                await RevokeHandler.handle(
                    peerSpkiFingerprint: fingerprint,
                    session: ControlRevokeHandlerSession(session: session),
                    trustStore: trustStore,
                    registry: ControlRevokeHandlerRegistry(registry: sessionRegistry, session: session)
                )
                return
            case .keyRotation(let message)?:
                await rotation?.handle(message)
            default:
                continue
            }
        }
    }
    return Task {
        _ = await worker.value
    }
}

/// Adapts a `.trusted` session to ``TandemStore/RevokeHandlerSession`` for
/// ``startControlRevokeReader(fingerprint:session:sessionRegistry:trustStore:)`` (E14-26). Reports
/// `.ready` synchronously rather than replaying `session.state`: that stream is
/// ``ConnectionStateMachine/states``, an unboundedly-buffered replay of every state this
/// connection has ever been in since ``ConnectionStateMachine/disconnected(reason:)`` at accept
/// time, and nothing in ``NWListenerFactory`` ever drains it -- a fresh reader over it would
/// therefore see the connection's *oldest* still-buffered state first (`.disconnected(reason:
/// nil)`), not its current one, wrongly reporting "not ready" to ``RevokeHandler/handle``'s own
/// readiness guard. This reader is spawned only once `NWListenerFactory`'s own
/// `handleReadyDecision(metadataIdentifier:session:)` has already registered this exact session as
/// `.trusted` and Ready, and it only ever sees a `Revoke` frame while that same session's
/// `CONTROL` channel is still open (``TandemSession/receive(_:)`` finishes once `close()` is
/// called), so asserting `.ready` here reflects the connection's true state at the moment this
/// fires.
private struct ControlRevokeHandlerSession: RevokeHandlerSession {
    let session: ByteStreamSession

    var state: AsyncStream<RevokeHandlerConnectionState> {
        AsyncStream { continuation in
            continuation.yield(.ready)
            continuation.finish()
        }
    }

    func close() async {
        await session.close()
    }
}

/// Adapts ``ControlSessionRegistering`` to ``TandemStore/RevokeHandlerRegistry`` for
/// ``startControlRevokeReader(fingerprint:session:sessionRegistry:trustStore:)`` (E14-26). Routes
/// through ``ControlSessionRegistering/removeIfCurrent(_:session:)`` (identity-checked) rather
/// than an unconditional removal-by-fingerprint, so a session this reader is about to revoke never
/// clobbers a newer session already registered for the same peer.
private struct ControlRevokeHandlerRegistry: RevokeHandlerRegistry {
    let registry: any ControlSessionRegistering
    let session: any TandemSession

    func unregister(_ spkiFingerprint: SpkiFingerprint) async {
        await registry.removeIfCurrent(spkiFingerprint, session: session)
    }
}
