import TandemCrypto
import TandemProtocol
import TandemStore

/// Spawned once a `.trusted` session is registered (E14-26, ``NWListenerFactory``'s own
/// `wireSession(adapter:metadataIdentifier:)`): reads `session`'s own `CONTROL` channel
/// (``HeartbeatController``'s own kdoc already reserves this exact stream for "a future `CONTROL`
/// reader" -- this is it) until either a `Revoke` frame arrives, dispatched to
/// ``TandemStore/RevokeHandler``, or the stream finishes on its own once `session` closes for any
/// other reason (``TandemSession/receive(_:)``'s own contract). A no-op task if `trustStore` is
/// `nil`. Every other `CONTROL` payload (`Heartbeat` included, already handled by
/// ``HeartbeatController`` off the non-consuming `received` broadcast) is ignored here and the
/// loop keeps reading.
///
/// A free function, not a method on ``NWListenerFactory``, purely so this file (kept small for
/// this repo's `file_length`/`type_body_length` SwiftLint budgets) can build its own adapters
/// without needing cross-file access to that type's own `private` stored properties -- every
/// dependency it needs is passed in explicitly.
func startControlRevokeReader(
    fingerprint: SpkiFingerprint,
    session: ByteStreamSession,
    sessionRegistry: any ControlSessionRegistering,
    trustStore: TrustStore?
) -> Task<Void, Never>? {
    guard let trustStore else { return nil }
    return Task {
        let frames = await session.receive(.control)
        for await frame in frames {
            guard case .revoke = frame.payload else { continue }
            await RevokeHandler.handle(
                peerSpkiFingerprint: fingerprint,
                session: ControlRevokeHandlerSession(session: session),
                trustStore: trustStore,
                registry: ControlRevokeHandlerRegistry(registry: sessionRegistry, session: session)
            )
            return
        }
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
