import Foundation
import TandemCrypto
import os

// Internal type definitions for the RevokeHandler.
// These mirror the actual TandemProtocol types and are used to avoid a circular dependency.
// The handler works with anything conforming to these protocols.

public protocol RevokeHandlerSession: Sendable {
    var state: AsyncStream<RevokeHandlerConnectionState> { get }
    func close() async
}

public enum RevokeHandlerConnectionState: Sendable, Equatable {
    case ready
    case other
}

public protocol RevokeHandlerRegistry: Sendable {
    func unregister(_ spkiFingerprint: SpkiFingerprint) async
}

/// Handles incoming Revoke messages: on a Ready trusted session, deletes the peer's trust record
/// and closes the session, plus any other live session of the same phone registered under another
/// of its pins (a key rotation changes the pin a session handshook with). Revoke on a
/// pairing-candidate connection or before Ready is ignored.
/// (E14-15, docs/protocol/SPEC.md #errors-and-close-codes row 7)
///
/// Public (E14-26) so a real composition root (``AppComposition``/`NWListenerFactory`) can wire
/// this exact handler into a live `CONTROL` reader instead of reimplementing its effect -- the
/// `RevokeHandlerSession`/`RevokeHandlerRegistry` mirror protocols above stay the seam that avoids
/// a `TandemStore` -> `TandemProtocol` dependency (this file's own top-of-file note); a caller in
/// another module adapts its real `TandemSession`/`ControlSessionRegistering` to them.
public struct RevokeHandler {
    /// Processes a Revoke message received on `session` from a peer identified by `peerSpkiFingerprint`.
    /// If the session is in Ready state, deletes the peer's trust record, closes the session, runs
    /// every registered purger for each fingerprint the peer's data may be keyed by and calls
    /// `onUnpaired`. If the session is not yet Ready, the revoke is ignored.
    public static func handle(
        peerSpkiFingerprint: SpkiFingerprint,
        session: any RevokeHandlerSession,
        trustStore: TrustStore,
        registry: any RevokeHandlerRegistry,
        purgeRegistry: PeerDataPurgeRegistry? = nil,
        onUnpaired: (@Sendable () async -> Void)? = nil
    ) async {
        // Only process Revoke on a Ready, trusted session
        var isReady = false
        for await state in session.state.prefix(1) {
            if case .ready = state {
                isReady = true
            }
            break
        }

        guard isReady else { return }

        let pins = (try? trustStore.pinnedFingerprints(for: peerSpkiFingerprint)) ?? [peerSpkiFingerprint]
        do {
            try trustStore.unpair(peerSpkiFingerprint)
        } catch {
            Logger(subsystem: "dev.tandem.store", category: "revoke").error("trust record delete failed")
        }

        await session.close()
        for pin in pins {
            await registry.unregister(pin)
        }
        await purgeRegistry?.purge(peers: pins)
        await onUnpaired?()
    }
}
