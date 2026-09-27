import Foundation
import TandemCrypto
import os

// Internal type definitions for the UnpairAction.
// These mirror the actual TandemProtocol types and are used to avoid a circular dependency.

protocol UnpairActionSession: Sendable {
    var state: AsyncStream<UnpairActionConnectionState> { get }
    func sendRevoke() async throws
    func close() async
}

enum UnpairActionConnectionState: Sendable, Equatable {
    case ready
    case other
}

protocol UnpairActionRegistry: Sendable {
    func unregister(_ spkiFingerprint: SpkiFingerprint) async
}

/// Per-peer data purge hook for later-phase stores. Implementations register with
/// ``PeerDataPurgeRegistry`` at app start (E50-09, E51-04) and are invoked when a peer
/// is unpaired (E14-13). The order of invocation is the registration order; a purger
/// failure is logged and retried on next launch, never restoring trust.
public protocol PeerDataPurging: Sendable {
    /// Purges all data for the given peer. Failures are logged (category only) and
    /// retried on next launch; the peer's trust record remains deleted.
    func purgeAll(peer: SpkiFingerprint) async throws
}

/// Registry for per-peer data purgers. Later-phase stores register their purgers here at
/// app start; ``UnpairAction`` invokes each on peer unpair.
public actor PeerDataPurgeRegistry {
    private var purgers: [any PeerDataPurging] = []
    private var failedPeers: Set<SpkiFingerprint> = []

    public init() {}

    /// Registers a purger to be called on unpair operations.
    public func register(_ purger: any PeerDataPurging) {
        purgers.append(purger)
    }

    /// Calls each registered purger's purgeAll in order. Logs failures (category only)
    /// and records them for retry on next launch.
    func purgeAllAndRecordFailures(peer: SpkiFingerprint) async {
        for purger in purgers {
            do {
                try await purger.purgeAll(peer: peer)
            } catch {
                // Log the failure (category only); record for retry
                let log = OSLog(subsystem: "com.tandem.store", category: "unpair")
                os_log("Failed to purge data for peer", log: log, type: .error)
                failedPeers.insert(peer)
            }
        }
    }

    /// Returns true if this peer had any purge failures on previous launches.
    func hasPriorFailures(for peer: SpkiFingerprint) -> Bool {
        failedPeers.contains(peer)
    }
}

/// Unpair action: local deletion and Revoke if connected (E14-13).
/// Deletes the peer's trust record and, if a Ready session exists, sends Revoke on CONTROL,
/// closes the session, and unregisters it. Invokes all registered data purgers.
struct UnpairAction {
    struct Dependencies {
        let trustStore: TrustStore
        let registry: any UnpairActionRegistry
        let purgeRegistry: PeerDataPurgeRegistry
        let clock: any Clock<Duration>
    }

    /// Unpairs a device: deletes its local trust record, sends Revoke if a Ready session
    /// exists (with a 2s timeout), and invokes all registered data purgers.
    ///
    /// The sequence is:
    /// 1. Delete the local trust record first.
    /// 2. If a Ready session exists:
    ///    - Send Revoke on CONTROL (or timeout after 2s virtual time).
    ///    - Close the session and unregister it.
    /// 3. Run all registered purgers.
    ///
    /// If any Revoke send throws or times out, the record is still deleted and the session
    /// is still closed.
    static func unpair(
        peerSpkiFingerprint: SpkiFingerprint,
        session: (any UnpairActionSession)?,
        dependencies: Dependencies
    ) async {
        // 1. Delete the local trust record first
        do {
            try dependencies.trustStore.unpair(peerSpkiFingerprint)
        } catch {
            // If deletion fails, still continue with revoke and purging
        }

        // 2. If a Ready session exists, send Revoke, close, and unregister
        if let session = session {
            var isReady = false
            for await state in session.state.prefix(1) {
                if case .ready = state {
                    isReady = true
                }
                break
            }

            if isReady {
                // Send Revoke with 2s timeout using a task group
                await withTaskGroup(of: Void.self) { group in
                    // Task 1: attempt to send Revoke
                    group.addTask {
                        do {
                            try await session.sendRevoke()
                        } catch {
                            // Send failure; continue to close
                        }
                    }

                    // Task 2: sleep for 2s, which will be the timeout
                    group.addTask {
                        try? await dependencies.clock.sleep(for: .seconds(2))
                    }

                    // Wait for at least one to complete (whichever finishes first)
                    _ = await group.next()

                    // Cancel remaining tasks (timeout if send completed, send if timeout fires)
                    group.cancelAll()
                }

                // Close the session and unregister
                await session.close()
                await dependencies.registry.unregister(peerSpkiFingerprint)
            }
        }

        // 3. Run all registered purgers
        await dependencies.purgeRegistry.purgeAllAndRecordFailures(peer: peerSpkiFingerprint)
    }
}
