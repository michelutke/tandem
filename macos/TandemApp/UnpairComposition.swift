import Foundation
import TandemCrypto
import TandemDevices
import TandemProtocol
import TandemStore

/// Composes the real ``TandemDevices/PairedDevicesViewModel`` (E14-14) with a real
/// ``TandemStore/UnpairAction`` (E14-26): the Devices screen's revoke button, once presented
/// somewhere in the app, actually deletes the peer's trust record and, if it's currently
/// connected, sends it `Revoke` and closes the session -- the same production ``UnpairAction``
/// its own tests exercise, not a reimplementation. Mirrors the incoming-`Revoke` side of E14-26
/// (`NWListenerFactory`'s own `CONTROL` reader, `TandemTransport`), which stays the one place that
/// dispatches to ``TandemStore/RevokeHandler`` -- this file only ever handles the *outgoing*,
/// owner-initiated unpair.
extension AppComposition {
    /// Builds a real ``TandemDevices/PairedDevicesViewModel`` wired to ``AppComposition/startListener()``'s
    /// own ``RetainedLifecycle`` -- the same ``TandemStore/TrustStore`` and
    /// ``TandemProtocol/ControlSessionRegistry`` the running listener reads/writes, so a peer this
    /// view model shows as connected is the exact one an unpair would find live.
    @MainActor
    static func makePairedDevicesViewModel(
        lifecycle: RetainedLifecycle,
        dateProvider: @escaping DateProvider = { Date() },
        clock: any Clock<Duration> = ContinuousClock()
    ) -> PairedDevicesViewModel {
        PairedDevicesViewModel(
            trustStore: lifecycle.trustStore,
            dateProvider: dateProvider,
            unpair: makeUnpairAction(
                trustStore: lifecycle.trustStore,
                sessionRegistry: lifecycle.sessionRegistry,
                purgeRegistry: lifecycle.purgeRegistry,
                clock: clock,
                onUnpaired: { await lifecycle.pairedPeer.refresh() }
            )
        )
    }

    /// The closure ``PairedDevicesViewModel/init(trustStore:dateProvider:unpair:)`` calls on
    /// confirmed revoke: looks up whether `fingerprint` currently has a live registered session
    /// (``ControlSessionRegistry/session(for:)``, E14-26) and runs the real
    /// ``TandemStore/UnpairAction/unpair(peerSpkiFingerprint:session:dependencies:)`` -- deleting
    /// the trust record first regardless, then sending `Revoke`/closing/unregistering only if a
    /// session was actually found.
    static func makeUnpairAction(
        trustStore: TrustStore,
        sessionRegistry: ControlSessionRegistry,
        purgeRegistry: PeerDataPurgeRegistry,
        clock: any Clock<Duration> = ContinuousClock(),
        onUnpaired: @escaping @Sendable () async -> Void = {}
    ) -> @Sendable (SpkiFingerprint) async throws -> Void {
        { fingerprint in
            let liveSession = await sessionRegistry.session(for: fingerprint)
            await UnpairAction.unpair(
                peerSpkiFingerprint: fingerprint,
                session: liveSession.map { UnpairActionSessionAdapter(session: $0) },
                dependencies: UnpairAction.Dependencies(
                    trustStore: trustStore,
                    registry: UnpairActionRegistryAdapter(registry: sessionRegistry, session: liveSession),
                    purgeRegistry: purgeRegistry,
                    clock: clock
                )
            )
            await onUnpaired()
        }
    }
}

/// Adapts a live ``TandemSession`` to ``UnpairActionSession`` (E14-26). Reports `.ready`
/// synchronously rather than replaying `session.state` -- exactly like `TandemTransport`'s own
/// `ControlRevokeHandlerSession` for the incoming-`Revoke` direction, and for the same reason:
/// `session.state` is ``ConnectionStateMachine/states``, an unboundedly-buffered replay of this
/// connection's entire history, so a fresh reader over it would see its *oldest* still-buffered
/// state, not its current one. This adapter is only ever built from a session this same call just
/// read out of ``ControlSessionRegistry`` (a peer appears there only once Ready and `.trusted`),
/// so asserting `.ready` reflects reality at the moment ``UnpairAction`` checks it.
private struct UnpairActionSessionAdapter: UnpairActionSession {
    let session: any TandemSession

    var state: AsyncStream<UnpairActionConnectionState> {
        AsyncStream { continuation in
            continuation.yield(.ready)
            continuation.finish()
        }
    }

    func sendRevoke() async throws {
        try await session.send(.control, payload: .revoke(Tandem_V1_Revoke()))
    }

    func close() async {
        await session.close()
    }
}

/// Adapts ``ControlSessionRegistry`` to ``UnpairActionRegistry`` (E14-26). Routes through
/// ``ControlSessionRegistering/removeIfCurrent(_:session:)`` (identity-checked) using the exact
/// session ``AppComposition/makeUnpairAction`` already looked up, so this never clobbers a newer
/// session registered for the same peer after that lookup. ``UnpairAction`` only ever calls
/// `unregister(_:)` when it was given a non-nil session, so `session == nil` here is unreachable
/// in practice and handled as a no-op rather than force-unwrapped.
private struct UnpairActionRegistryAdapter: UnpairActionRegistry {
    let registry: ControlSessionRegistry
    let session: (any TandemSession)?

    func unregister(_ spkiFingerprint: SpkiFingerprint) async {
        guard let session else { return }
        await registry.removeIfCurrent(spkiFingerprint, session: session)
    }
}
