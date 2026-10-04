import TandemCrypto

/// Read/write surface a session-wiring caller (e.g. `TandemTransport`'s `NWListenerFactory`, E12-12)
/// needs from ``ControlSessionRegistry`` -- a seam so a test can inject a spy and observe
/// registration without reaching into this actor's private state.
public protocol ControlSessionRegistering: Sendable {
    func register(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async
    func removeIfCurrent(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async
}

/// Tracks one Ready control session per peer SPKI (invariant 3, E12-19). When a second connection
/// for the same peer SPKI reaches Ready, the registry closes the previously-registered session with
/// `limitExceeded` before registering the new one. Keyed strictly by SPKI fingerprint; no lookup
/// or registration path accepts an IP address, hostname, or device ID.
public actor ControlSessionRegistry: ControlSessionRegistering {
    private var sessions: [SpkiFingerprint: any TandemSession] = [:]

    public init() {}

    /// Registers `session` for the given `spkiFingerprint`. If a session already exists for this
    /// fingerprint, closes it with `limitExceeded` before registering the new one.
    public func register(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async {
        if let oldSession = sessions[spkiFingerprint] {
            await oldSession.close()
        }
        sessions[spkiFingerprint] = session
    }

    /// Closes and removes the session for the given SPKI fingerprint, if one exists.
    public func unregister(_ spkiFingerprint: SpkiFingerprint) async {
        if let session = sessions.removeValue(forKey: spkiFingerprint) {
            await session.close()
        }
    }

    /// The currently registered session for `spkiFingerprint`, if this peer is presently connected
    /// -- `nil` otherwise. E14-26: lets a composition root (``AppComposition``'s Devices-screen
    /// unpair wiring) look up whether a peer has a live session to send `Revoke` on before
    /// deleting its trust record, without exposing this actor's private storage directly. Not part
    /// of ``ControlSessionRegistering`` (every existing conformer/spy stays unaffected); callers
    /// that need this hold the concrete actor, exactly like ``AppComposition`` already does for
    /// ``register(_:session:)``'s own construction site.
    public func session(for spkiFingerprint: SpkiFingerprint) -> (any TandemSession)? {
        sessions[spkiFingerprint]
    }

    /// Whether `session` is exactly the one registered for `spkiFingerprint` (E22-12): a session
    /// reported by a handshake that failed before registering, or one already replaced, is not.
    public func isRegistered(_ session: any TandemSession, for spkiFingerprint: SpkiFingerprint) -> Bool {
        guard let current = sessions[spkiFingerprint] else { return false }
        return current === session
    }

    /// Whether `session`'s state may be surfaced for `spkiFingerprint` (E15-16): the registered
    /// session itself, or any session while none is registered (a handshake that failed before
    /// ever registering, e.g. a version mismatch). `false` for an unregistered session while a
    /// different live one is registered, so a stale failure never overrides a connected peer.
    public func shouldForwardState(of session: any TandemSession, for spkiFingerprint: SpkiFingerprint) -> Bool {
        guard let current = sessions[spkiFingerprint] else { return true }
        return current === session
    }

    /// Removes and closes the session for `spkiFingerprint` only if it is still exactly `session`
    /// (identity-checked, since both are actor references) -- so a disconnect notification for an
    /// older, already-replaced session never removes a newer session registered later for the same
    /// SPKI (`register`'s own `limitExceeded` replacement already closed the older one).
    public func removeIfCurrent(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async {
        guard let current = sessions[spkiFingerprint], current === session else { return }
        sessions.removeValue(forKey: spkiFingerprint)
        await current.close()
    }
}

/// `TandemSession` conformances are always reference types (``ByteStreamSession`` is an `actor`;
/// `FakeTandemSession` in tests is too) -- this operator lets ``ControlSessionRegistry`` compare
/// two `any TandemSession` existentials by identity without adding an `AnyObject` constraint to the
/// protocol itself (which every conformance already satisfies in practice, but the protocol is
/// otherwise transport-agnostic on purpose, per its own kdoc).
private func === (lhs: any TandemSession, rhs: any TandemSession) -> Bool {
    (lhs as AnyObject) === (rhs as AnyObject)
}
