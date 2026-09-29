import Network
import Security
import TandemCrypto
import TandemProtocol

/// The single ALPN identifier this protocol negotiates (`docs/protocol/SPEC.md`
/// `#handshake-and-tls-profile`). No other value is ever offered or accepted.
public let tandemALPN = "tandem/1"

public enum ListenerFactoryError: Error, Sendable, Equatable {
    case invalidIdentity
}

/// `sec_protocol_verify_t`, spelled out so `@Sendable` can attach to the underlying function type
/// directly -- `@Sendable sec_protocol_verify_t` is rejected ("attribute does not apply to type")
/// when used as a *stored property*'s type (only as a parameter's), since `@Sendable`/`@escaping`
/// can only attach to literal function-type syntax, not to a bare typealias reference. Same
/// runtime shape as `sec_protocol_verify_t` (`SecProtocolOptions.h`), just written so both
/// ``ListenerFactory`` call sites and ``ListenerController``'s stored property compile.
public typealias TandemVerifyBlock = @Sendable (
    sec_protocol_metadata_t,
    sec_trust_t,
    @escaping sec_protocol_verify_complete_t
) -> Void

/// Builds the app's single mTLS `NWListener` (E12-01). This is a seam so
/// ``ListenerController`` can be unit-tested with a recording fake that never constructs a real
/// `NWListener`.
///
/// Scope is deliberately narrow: TLS 1.3-only, a required client certificate, and the ALPN
/// `tandem/1` -- nothing else. One thing is an explicit non-goal of this type, left to a later
/// issue so a future reader doesn't "helpfully" add it here: the `verify` block's actual trust
/// decision (matching the peer's SPKI against the trust store or an open pairing window) is
/// E12-02 (``PeerVerifier``); this type only wires whatever block it is given into
/// `sec_protocol_options_set_verify_block`. The one exception is admission (E12-18,
/// ``ConnectionAdmission``): every accepted connection is consulted against it, before the TLS
/// handshake starts, since that is the only point at which an over-cap or throttled connection can
/// be closed "before any allocation or side effect it would otherwise cause" (SPEC.md §10).
///
/// No session resumption, no 0-RTT (E12-03, `docs/protocol/SPEC.md` §1): the server MUST NOT issue
/// a usable session ticket, and neither side may resume a session -- disabling both
/// `sec_protocol_options_set_tls_tickets_enabled` (issuance) and
/// `sec_protocol_options_set_tls_resumption_enabled` (offer/accept) leaves no PSK for a subsequent
/// connection to offer, which is also what rules out 0-RTT/early data: TLS 1.3 early data requires
/// a PSK from a prior session, and none is ever issued (spike E03-01 §6: 0/20 tickets observed
/// with tickets both explicitly off and explicitly on, once client-certificate auth is in play).
///
/// D-67 (channel binding): this type and the connections it hands off never call any TLS
/// metadata secret/key-export primitive and expose no channel-binding API of any kind --
/// channel binding in this protocol is an in-band application-layer challenge (`PairChallenge` /
/// `RotationChallenge`), never an RFC 9266 TLS key-export mechanism (`docs/planning/decisions.md`
/// D-67).
public protocol ListenerFactory: Sendable {
    func makeListener(
        identity: SecIdentity,
        port: NWEndpoint.Port,
        verify: @escaping @Sendable sec_protocol_verify_t,
        admission: ConnectionAdmission
    ) throws -> NWListener
}

extension NWListenerFactory {
    /// Called right after a `.trusted` session is registered under its SPKI fingerprint (E22-11)
    /// -- a purely additive composition-root seam, `nil` by default for every existing caller, so
    /// ``AppComposition`` can forward a real, currently-paired peer's ``TandemSession/state`` into
    /// its own long-lived relay without this package knowing anything about the menu bar.
    public typealias SessionRegisteredHandler = @Sendable (SpkiFingerprint, any TandemSession) -> Void
}
