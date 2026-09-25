@preconcurrency import Security

/// The Keychain identity's lifecycle state, as ``ListenerController`` sees it (E12-01). This is
/// the seam `ListenerController` uses to decide whether it may ever construct a listener: it must
/// never open a socket without a ready identity (UC-01, invariant 4's spirit extended to "no
/// listener without identity"). E10-09 (identity lifecycle bootstrap, not yet implemented) will
/// supply the real conforming type, transitioning between these three states as the Keychain
/// identity is created, loaded, or fails; tests here use a fixed-value fake.
public enum IdentityState: Sendable {
    /// The identity exists and is usable as a TLS local identity.
    case ready(SecIdentity)
    /// No identity has been created yet.
    case missing
    /// Identity creation or loading failed. The string is a plain, human-readable reason -- never
    /// raw certificate or key bytes (invariant 7, log/secret hygiene).
    case error(String)
}

/// Supplies the current ``IdentityState``. E10-09 provides the real, lifecycle-aware conforming
/// type; tests use a fixed-value fake.
public protocol IdentityStateProvider: Sendable {
    var identityState: IdentityState { get }
}
