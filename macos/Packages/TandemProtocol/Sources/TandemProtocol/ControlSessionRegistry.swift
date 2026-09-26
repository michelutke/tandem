import TandemCrypto

/// Tracks one Ready control session per peer SPKI (invariant 3, E12-19). When a second connection
/// for the same peer SPKI reaches Ready, the registry closes the previously-registered session with
/// `limitExceeded` before registering the new one. Keyed strictly by SPKI fingerprint; no lookup
/// or registration path accepts an IP address, hostname, or device ID.
public actor ControlSessionRegistry {
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
}
