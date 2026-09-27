import Network
import os
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

/// Production ``ListenerFactory``. Binds to every interface (not loopback-only, unlike the test
/// harnesses in this package) on `port`, so a real phone on the LAN can reach it -- `port`
/// selection itself is out of scope here (the pairing QR's `p` field, `docs/protocol/SPEC.md`
/// `#pairing`); this type just listens on whatever port it is given.
public struct NWListenerFactory: ListenerFactory {
    /// Where a connection that reaches `.ready` as a `.trusted` peer is registered under its SPKI
    /// fingerprint (E12-19). `any ControlSessionRegistering` rather than the concrete actor so a
    /// test can inject a spy. Shared across every connection this listener ever accepts.
    private let sessionRegistry: any ControlSessionRegistering
    /// Recovers the decision and fingerprint `PeerVerifier`'s `onDecision` hook already computed
    /// for a connection's own verify callback (E12-02), keyed by that connection's TLS metadata
    /// object.
    private let decisionCorrelator: PeerDecisionCorrelator
    /// Drives `ConnectionStateMachine`'s handshake deadline and `VersionHandshake`'s hello
    /// deadline for every session this listener wires up (E00-24 seam rule).
    private let clock: any Clock<Duration>
    /// Where a `.pairingCandidate` connection's pairing dance (E14-09) is handed off once its
    /// `VersionHello` exchange completes; `nil` means this listener never admits pairing
    /// candidates in the first place (e.g. the E15-22 CI harness's plain `-HarnessListenerPort`,
    /// which always runs a `NeverOpenPairingWindow`), so such a decision would never occur.
    private let pairingCandidateDriver: (any PairingCandidateDriver)?

    private static let logger = Logger(subsystem: "dev.tandem.transport", category: "NWListenerFactory")

    public init(
        sessionRegistry: any ControlSessionRegistering,
        decisionCorrelator: PeerDecisionCorrelator,
        clock: any Clock<Duration> = ContinuousClock(),
        pairingCandidateDriver: (any PairingCandidateDriver)? = nil
    ) {
        self.sessionRegistry = sessionRegistry
        self.decisionCorrelator = decisionCorrelator
        self.clock = clock
        self.pairingCandidateDriver = pairingCandidateDriver
    }

    public func makeListener(
        identity: SecIdentity,
        port: NWEndpoint.Port,
        verify: @escaping @Sendable sec_protocol_verify_t,
        admission: ConnectionAdmission
    ) throws -> NWListener {
        guard let secIdentity = sec_identity_create(identity) else {
            throw ListenerFactoryError.invalidIdentity
        }

        let tlsOptions = NWProtocolTLS.Options()
        let sec = tlsOptions.securityProtocolOptions

        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_local_identity(sec, secIdentity)
        sec_protocol_options_set_peer_authentication_required(sec, true)
        sec_protocol_options_add_tls_application_protocol(sec, tandemALPN)
        sec_protocol_options_set_tls_tickets_enabled(sec, false)
        sec_protocol_options_set_tls_resumption_enabled(sec, false)
        sec_protocol_options_set_verify_block(sec, verify, .global())

        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        let listener = try NWListener(using: parameters, on: port)

        listener.newConnectionHandler = { connection in
            guard let ipAddress = Self.remoteHost(of: connection) else {
                connection.cancel()
                return
            }

            Task {
                await admitAndStart(connection: connection, ipAddress: ipAddress, admission: admission)
            }
        }

        return listener
    }

    /// Consults `admission` for `connection`'s source address and, if admitted, wires up its
    /// `stateUpdateHandler` and starts it; a refusal cancels `connection` before any TLS handshake
    /// starts (SPEC.md §10).
    private func admitAndStart(
        connection: NWConnection,
        ipAddress: String,
        admission: ConnectionAdmission
    ) async {
        let decision = await admission.accept(ipAddress: ipAddress) {
            connection.cancel()
        }

        switch decision {
        case .refused:
            connection.cancel()
        case .admitted(let id):
            let adapter = NWConnectionByteStreamConnection(connection: connection)
            connection.stateUpdateHandler = makeStateUpdateHandler(
                connection: connection,
                admission: admission,
                id: id,
                adapter: adapter
            )
            connection.start(queue: .global())
        }
    }

    /// Builds `connection`'s `stateUpdateHandler`, reporting this connection's eventual outcome
    /// back to `admission` (E12-18) alongside the existing ALPN check (E12-01), and republishing
    /// every transition onto `adapter`'s own ``ByteStreamConnection/state`` stream -- `NWConnection`
    /// allows only one `stateUpdateHandler`, so this single closure is the one place both
    /// concerns can observe the connection's lifecycle. Once `.ready` passes the ALPN check, spawns
    /// the E12-12 session wiring (``wireSession(adapter:connection:)``).
    private func makeStateUpdateHandler(
        connection: NWConnection,
        admission: ConnectionAdmission,
        id: ConnectionAdmission.ConnectionID,
        adapter: NWConnectionByteStreamConnection
    ) -> @Sendable (NWConnection.State) -> Void {
        { state in
            switch state {
            case .ready:
                let rawMetadata = connection.metadata(definition: NWProtocolTLS.definition)
                guard
                    let metadata = rawMetadata as? NWProtocolTLS.Metadata,
                    let negotiated = sec_protocol_metadata_get_negotiated_protocol(
                        metadata.securityProtocolMetadata
                    ),
                    String(cString: negotiated) == tandemALPN
                else {
                    if let metadata = rawMetadata as? NWProtocolTLS.Metadata {
                        let dropped = decisionCorrelator.drop(
                            metadataIdentifier: ObjectIdentifier(metadata.securityProtocolMetadata)
                        )
                        abandonIfPairingCandidate(dropped)
                    }
                    connection.cancel()
                    Task { await admission.handshakeFailed(id) }
                    return
                }
                adapter.reportReady()
                let metadataIdentifier = ObjectIdentifier(metadata.securityProtocolMetadata)
                Task {
                    await admission.handshakeSucceeded(id)
                    // E20-10/E20-11: lets a later `ListenerControl.stop()` (sleep, or a rebind on
                    // network path change) tear this connection down to `Disconnected` -- the
                    // only place any *post*-handshake connection is tracked at all.
                    await admission.trackReadyConnection(id) { connection.cancel() }
                }
                Task { await wireSession(adapter: adapter, metadataIdentifier: metadataIdentifier) }
            case .failed(let error):
                // A rejected handshake (bad TLS version, no client cert, ALPN mismatch) never
                // reaches `.ready`, so without this the accepted `NWConnection` is only ever
                // released by `.cancelled` -- which nothing here would ever trigger for it --
                // leaking it (and its closure's strong self-reference) for the life of the
                // process. Cancelling on `.failed` releases it, and counts as a failed handshake
                // for the per-IP throttle (SPEC.md §10). A connection that had already reached
                // `.ready` and is only failing later (peer vanished after the handshake) is also
                // untracked here, so a subsequent `cancelAllReady()` never revisits it.
                adapter.reportFailed("\(error)")
                abandonIfPairingCandidate(
                    Self.dropStaleDecision(connection: connection, decisionCorrelator: decisionCorrelator)
                )
                connection.cancel()
                Task {
                    await admission.handshakeFailed(id)
                    await admission.untrackReadyConnection(id)
                }
            case .cancelled:
                // Reached either from one of the `connection.cancel()` calls above (already
                // reported, so this is a no-op), from `ConnectionAdmission.cancelAllReady()`
                // cancelling an already-`.ready` connection (E20-10/E20-11), or from the TCP
                // connection itself closing/resetting before the handshake ever reached
                // `.ready`/`.failed` -- also a failed handshake (SPEC.md §10).
                adapter.reportCancelled()
                abandonIfPairingCandidate(
                    Self.dropStaleDecision(connection: connection, decisionCorrelator: decisionCorrelator)
                )
                Task {
                    await admission.handshakeFailed(id)
                    await admission.untrackReadyConnection(id)
                }
            default:
                break
            }
        }
    }

    /// A connection that never reaches `.ready` (verify rejected it, or it reset/timed out first)
    /// may still have a decision recorded for it (E12-02's `onDecision` fires before `complete(_:)`
    /// regardless of outcome) -- drop it so a *later* connection can never inherit a stale
    /// `.trusted` decision through a reused `sec_protocol_metadata_t` `ObjectIdentifier` (finding
    /// #3: the address-reuse race this guards against). Returns the dropped entry, if any, so the
    /// caller can still release a `.pairingCandidate` connection's window slot (E14-16 finding #1).
    @discardableResult
    private static func dropStaleDecision(
        connection: NWConnection,
        decisionCorrelator: PeerDecisionCorrelator
    ) -> PeerDecisionCorrelator.Decision? {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            return nil
        }
        return decisionCorrelator.drop(metadataIdentifier: ObjectIdentifier(metadata.securityProtocolMetadata))
    }

    /// Releases `dropped`'s window slot (E14-16 finding #1) if it was ever recorded and was a
    /// `.pairingCandidate` decision -- every other case (no entry at all, `.trusted`, `.rejected`)
    /// is a no-op, since neither of those ever claims the slot in the first place. Fire-and-forget
    /// (`Task`), matching every other post-hoc admission report already made from this same
    /// synchronous `stateUpdateHandler` closure.
    private func abandonIfPairingCandidate(_ dropped: PeerDecisionCorrelator.Decision?) {
        guard let dropped, dropped.decision == .pairingCandidate, let token = dropped.candidateToken else { return }
        guard let driver = pairingCandidateDriver else { return }
        Task { await driver.candidateAbandoned(token: token) }
    }

    /// Wraps `adapter` in a real `ChannelMultiplexer` + `ConnectionStateMachine`, runs the E12-07
    /// `VersionHandshake`, and -- once Ready -- registers the resulting `ByteStreamSession` in
    /// ``sessionRegistry`` under the peer's leaf SPKI fingerprint, but only if `PeerVerifier`
    /// (recovered from ``decisionCorrelator``, never re-derived) classified this peer `.trusted`;
    /// a `.pairingCandidate` connection reaching Ready is never registered here (E14's own pairing
    /// flow owns that handshake, once it exists). Every fatal outcome -- a failed/mismatched
    /// handshake, or the multiplexer closing for any reason (peer/framing/credit violation,
    /// transport failure, orderly peer close) -- cancels `adapter`'s underlying `NWConnection` and,
    /// once registered, identity-checked-removes this exact session from ``sessionRegistry`` so a
    /// dead session is never left registered.
    private func wireSession(adapter: NWConnectionByteStreamConnection, metadataIdentifier: ObjectIdentifier) async {
        let source = ByteStreamConnectionFrameSource(adapter)
        let multiplexer = ChannelMultiplexer(source: source, sink: { data in try await adapter.send(data) })
        let stateMachine = ConnectionStateMachine(clock: clock)
        let handshake = VersionHandshake(multiplexer: multiplexer, clock: clock)
        let session = ByteStreamSession(multiplexer: multiplexer, stateMachine: stateMachine)

        await stateMachine.handle(.incomingConnection)
        await stateMachine.handle(.handshakeStarted)
        await stateMachine.handle(.handshakeCompleted)
        await multiplexer.start()

        await handshake.run()
        var heartbeatController: HeartbeatController?
        switch await handshake.session {
        case .ready:
            await stateMachine.handle(.compatibleHelloReceived)
            heartbeatController = await makeHeartbeatController(
                session: session,
                stateMachine: stateMachine,
                multiplexer: multiplexer,
                adapter: adapter
            )
        case .failed(let failure):
            let closeCode: CloseCode
            switch failure {
            case .versionMismatch: closeCode = .versionMismatch
            case .protocolTimeout: closeCode = .protocolTimeout
            }
            await stateMachine.handle(.handshakeError(closeCode))
            adapter.cancel()
            abandonIfPairingCandidate(decisionCorrelator.drop(metadataIdentifier: metadataIdentifier))
            return
        case .pending:
            abandonIfPairingCandidate(decisionCorrelator.drop(metadataIdentifier: metadataIdentifier))
            return // `run()` always resolves `session` before returning; unreachable.
        }

        let registeredFingerprint = await handleReadyDecision(metadataIdentifier: metadataIdentifier, session: session)

        // Every path here already funnels through `ChannelMultiplexer.finish(_:)` -- a peer/
        // framing/credit violation, the peer's own orderly close, or a transport-level read
        // failure (which a cancelled/failed `NWConnection` also produces, via its `.receive()`
        // completion) -- so this single `awaitClose()` is where a Ready connection's demise, from
        // any cause, both reaches the state machine and cancels the socket (fail closed, SPEC.md
        // invariant 5).
        let closeReason = await multiplexer.awaitClose()
        await heartbeatController?.stop()
        await stateMachine.handle(.socketClosed(reason: "\(closeReason)"))
        adapter.cancel()
        if let registeredFingerprint {
            await sessionRegistry.removeIfCurrent(registeredFingerprint, session: session)
        }
    }

    /// Acts on the decision ``PeerVerifier`` recorded for this now-Ready connection: registers a
    /// `.trusted` session under its fingerprint (returned so ``wireSession`` can later remove it),
    /// hands a `.pairingCandidate` session off to ``pairingCandidateDriver`` (registering neither,
    /// E12-19), and otherwise does nothing (`.rejected` reaching Ready would itself be a bug, and a
    /// missing entry means the "verify-block metadata == `.ready` metadata" premise
    /// (`PeerDecisionCorrelator`'s own kdoc) failed -- logged so that's visible rather than a
    /// session that's Ready but was never registered or handed off anywhere).
    private func handleReadyDecision(
        metadataIdentifier: ObjectIdentifier,
        session: ByteStreamSession
    ) async -> SpkiFingerprint? {
        guard let recorded = decisionCorrelator.take(metadataIdentifier: metadataIdentifier) else {
            Self.logger.error("no PeerDecisionCorrelator entry for a connection that reached Ready")
            return nil
        }

        switch recorded.decision {
        case .trusted:
            guard let fingerprint = recorded.fingerprint else { return nil }
            await sessionRegistry.register(fingerprint, session: session)
            return fingerprint
        case .pairingCandidate:
            guard let driver = pairingCandidateDriver, let token = recorded.candidateToken else { return nil }
            guard let spkiDer = recorded.spkiDer else {
                // Unreachable in practice (`PeerVerifier` never records `.pairingCandidate` without
                // a parsed SPKI DER) -- handled anyway so this candidate's slot is never left
                // occupied for the rest of the window's 120 s (E14-16 finding #1).
                await driver.candidateAbandoned(token: token)
                return nil
            }
            await driver.drive(session: session, handshakeSpkiDer: spkiDer, token: token)
            return nil
        case .rejected:
            return nil
        }
    }

    /// Builds and starts this connection's ``HeartbeatController`` (E20-05), once the E12-07
    /// handshake has resolved `.ready`: the Mac half of the E01-07 liveness contract, and D-61's
    /// `CONTROL` receive cap. Split out of ``wireSession(adapter:metadataIdentifier:)`` purely to
    /// keep that function under this repo's `function_body_length` lint budget.
    private func makeHeartbeatController(
        session: ByteStreamSession,
        stateMachine: ConnectionStateMachine,
        multiplexer: ChannelMultiplexer,
        adapter: NWConnectionByteStreamConnection
    ) async -> HeartbeatController {
        let heartbeat = HeartbeatController(
            session: session,
            stateMachine: stateMachine,
            sent: multiplexer.sent,
            received: multiplexer.received,
            clock: clock,
            cancelConnection: { adapter.cancel() }
        )
        await heartbeat.start()
        return heartbeat
    }

    /// The remote endpoint's host, as ``ConnectionAdmission`` needs it -- a throttling key only,
    /// never a trust input (invariant 3). `nil` only if `Network` ever hands back an accepted
    /// connection whose endpoint isn't `.hostPort` at all, which never happens for a TCP listener
    /// in practice; such a connection is cancelled outright rather than guessed at.
    private static func remoteHost(of connection: NWConnection) -> String? {
        guard case .hostPort(let host, _) = connection.endpoint else { return nil }
        return "\(host)"
    }
}
