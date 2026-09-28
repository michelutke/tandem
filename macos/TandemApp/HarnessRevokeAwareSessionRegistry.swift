#if DEBUG
import Foundation
import TandemCrypto
import TandemProtocol
import TandemStore

/// DEBUG-only decorator (E14-20) around the harness listener's ``ControlSessionRegistry``: no real
/// composition root -- not ``AppComposition``'s ordinary listener, not this harness's own, until now
/// -- ever reacts to an incoming `Revoke` on a Ready session (``TandemStore/RevokeHandler`` exists
/// and is unit-tested, E14-15, but nothing calls it), so a phone-initiated unpair against the real
/// Mac app would otherwise leave its trust record behind forever. Every ``register(_:session:)``
/// starts a background watch of that session's own CONTROL channel for a `Revoke` frame and, on one,
/// deletes the peer's trust record and closes/unregisters the session -- reproducing
/// `RevokeHandler.handle`'s exact effect (delete, close, unregister; no reply sent) using only this
/// module's already-public API, so `TandemStore`'s own internal `RevokeHandler`/`UnpairAction` types
/// need no visibility change for a test harness.
///
/// With `-HarnessRevokeOnReady YES` also set, additionally performs a Mac-initiated revoke the
/// instant any peer's session reaches Ready and registers -- deletes that peer's trust record, sends
/// it a `Revoke` on CONTROL, then closes/unregisters -- the same way `-HarnessAutoConfirmPairing YES`
/// auto-clicks "Pair" the instant a confirmation code is computed, so a driver script never needs a
/// live command channel into this already-running process.
final class HarnessRevokeAwareSessionRegistry: ControlSessionRegistering, Sendable {
    private let wrapped: ControlSessionRegistry
    private let trustStore: TrustStore
    private let revokeOnReady: Bool

    init(wrapping registry: ControlSessionRegistry, trustStore: TrustStore, revokeOnReady: Bool) {
        self.wrapped = registry
        self.trustStore = trustStore
        self.revokeOnReady = revokeOnReady
    }

    func register(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async {
        await wrapped.register(spkiFingerprint, session: session)
        Task { [wrapped, trustStore] in
            for await frame in await session.receive(.control) {
                if case .revoke = frame.payload {
                    do {
                        try trustStore.unpair(spkiFingerprint)
                    } catch {
                        // Best-effort, matching RevokeHandler.handle's own "still proceed" behavior.
                    }
                    await wrapped.removeIfCurrent(spkiFingerprint, session: session)
                    print("harness-revoke-received: \(spkiFingerprint.hexString)")
                    fflush(stdout)
                    return
                }
            }
        }
        if revokeOnReady {
            do {
                try trustStore.unpair(spkiFingerprint)
            } catch {
                // Best-effort, matching UnpairAction.unpair's own "still proceed" behavior.
            }
            try? await session.send(.control, payload: .revoke(Tandem_V1_Revoke()))
            await wrapped.removeIfCurrent(spkiFingerprint, session: session)
            print("harness-revoke-sent: \(spkiFingerprint.hexString)")
            fflush(stdout)
        }
    }

    func removeIfCurrent(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async {
        await wrapped.removeIfCurrent(spkiFingerprint, session: session)
    }
}
#endif
