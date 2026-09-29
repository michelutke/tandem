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
///
/// `-HarnessStreamStatus YES` (E23-08) adds a second, independent piece of scaffolding: printing
/// every `DeviceStatus` frame a registered session's STATUS channel receives, for a driver script
/// to observe E23-03's throttle decision (how many frames actually reached the wire, and when)
/// without reaching into `AppComposition`'s own `DeviceStatusViewModel` -- which would race this
/// same tap for frames, since `ChannelMultiplexer.inbound(_:)`'s own kdoc documents one
/// `AsyncStream` per channel (a second concurrent consumer would split frames with this one,
/// rather than both seeing every frame). `HarnessStatusRingCommands` (E23-08) is the Mac-side
/// Ring/RingStop counterpart, driven over stdin instead of a registration-time hook, since
/// sending is driver-initiated rather than reactive.
final class HarnessRevokeAwareSessionRegistry: ControlSessionRegistering, Sendable {
    private let wrapped: ControlSessionRegistry
    private let trustStore: TrustStore
    private let revokeOnReady: Bool
    private let streamStatus: Bool

    init(
        wrapping registry: ControlSessionRegistry,
        trustStore: TrustStore,
        revokeOnReady: Bool,
        streamStatus: Bool = false
    ) {
        self.wrapped = registry
        self.trustStore = trustStore
        self.revokeOnReady = revokeOnReady
        self.streamStatus = streamStatus
    }

    func register(_ spkiFingerprint: SpkiFingerprint, session: any TandemSession) async {
        await wrapped.register(spkiFingerprint, session: session)
        if streamStatus {
            Task { await Self.streamDeviceStatus(session: session) }
        }
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

    /// Prints `harness-status-received: <epochMillis> battery=<n> charging=<bool>
    /// network=<name> signal=<n>`, one line per `DeviceStatus` frame, in arrival order --
    /// `RingStop{origin: phone}` and any other STATUS-channel payload are silently ignored (no
    /// scenario using `-HarnessStreamStatus YES` needs the Mac to react to those).
    private static func streamDeviceStatus(session: any TandemSession) async {
        let stream = await session.receive(.status)
        for await frame in stream {
            guard case .deviceStatus(let status)? = frame.payload else { continue }
            let epochMillis = Int64((Date().timeIntervalSince1970 * 1000).rounded())
            print(
                "harness-status-received: \(epochMillis) battery=\(status.batteryLevel) " +
                    "charging=\(status.isCharging) network=\(status.networkType) signal=\(status.signalLevel)"
            )
            fflush(stdout)
        }
    }
}
#endif
