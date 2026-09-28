#if DEBUG
import Foundation
import TandemCrypto
import TandemProtocol
import TandemStore

/// DEBUG-only decorator (E14-20) around the harness listener's ``ControlSessionRegistry``: only
/// `-HarnessRevokeOnReady YES`'s Mac-initiated-revoke test scaffolding lives here now (E14-27).
/// Every ``register(_:session:)``, with that flag set, performs a Mac-initiated revoke the instant
/// a peer's session reaches Ready and registers -- deletes that peer's trust record, sends it a
/// `Revoke` on CONTROL, then closes/unregisters -- the same way `-HarnessAutoConfirmPairing YES`
/// auto-clicks "Pair" the instant a confirmation code is computed, so a driver script never needs a
/// live command channel into this already-running process. This has no real-production equivalent
/// by design -- production never auto-revokes a peer on Ready -- so it has nowhere else to live.
///
/// Incoming-Revoke consumption (a phone unpairing against this harness listener) no longer lives
/// here: `HarnessHooks.startListenerIfRequested()` now passes its own `trustStore:` into
/// `NWListenerFactory`, so the harness listener's `CONTROL` reader is the exact same
/// `ControlRevokeConsumer`/`RevokeHandler` path `AppComposition`'s production listener uses
/// (E14-26/E14-27), not a parallel reimplementation racing it on the same session's frame stream.
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
        guard revokeOnReady else { return }
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

    func removeIfCurrent(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async {
        await wrapped.removeIfCurrent(spkiFingerprint, session: session)
    }
}
#endif
