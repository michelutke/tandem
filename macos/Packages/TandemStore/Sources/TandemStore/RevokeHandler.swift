import Foundation
import TandemCrypto

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
/// and closes the session. Revoke on a pairing-candidate connection or before Ready is ignored.
/// (E14-15, docs/protocol/SPEC.md #errors-and-close-codes row 7)
///
/// Public (E14-26) so a real composition root (``AppComposition``/`NWListenerFactory`) can wire
/// this exact handler into a live `CONTROL` reader instead of reimplementing its effect -- the
/// `RevokeHandlerSession`/`RevokeHandlerRegistry` mirror protocols above stay the seam that avoids
/// a `TandemStore` -> `TandemProtocol` dependency (this file's own top-of-file note); a caller in
/// another module adapts its real `TandemSession`/`ControlSessionRegistering` to them.
public struct RevokeHandler {
    /// Processes a Revoke message received on `session` from a peer identified by `peerSpkiFingerprint`.
    /// If the session is in Ready state, deletes the peer's trust record and closes the session.
    /// If the session is not yet Ready, the revoke is ignored.
    public static func handle(
        peerSpkiFingerprint: SpkiFingerprint,
        session: any RevokeHandlerSession,
        trustStore: TrustStore,
        registry: any RevokeHandlerRegistry
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

        // Delete the peer's trust record
        do {
            try trustStore.unpair(peerSpkiFingerprint)
        } catch {
            // If deletion fails (e.g., record doesn't exist, keychain locked),
            // still proceed to close the session
        }

        // Close the session and remove it from the registry
        await session.close()
        await registry.unregister(peerSpkiFingerprint)
    }
}
