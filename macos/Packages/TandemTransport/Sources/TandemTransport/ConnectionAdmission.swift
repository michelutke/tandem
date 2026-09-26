import Foundation

/// Pre-authentication admission control for the Mac's single mTLS listener (E12-18,
/// `docs/protocol/SPEC.md` §10 "Pre-authentication deadlines and connection caps"): at most 8
/// concurrent not-yet-Ready connections total and 2 per source IP (excess refused on accept,
/// before the TLS handshake starts), a 10 s TLS handshake deadline, and a per-source-IP
/// failed-handshake throttle (>= 10 failed handshakes within a rolling 60 s window refuses that
/// IP for 60 s).
///
/// A pure, unit-testable actor (E00-24 seam rule): every deadline and throttle window is driven
/// by an injected `any Clock<Duration>` (``TandemTestSupport/ManualTestClock`` in tests, exactly
/// like `TandemProtocol.ConnectionStateMachine`'s own TLS-deadline race) rather than wall-clock
/// time, and it never touches `Network` or a real socket itself -- ``NWListenerFactory`` calls
/// ``accept(ipAddress:onHandshakeDeadline:)`` on every accepted connection and acts on the
/// decision, and reports that connection's eventual outcome back via
/// ``handshakeSucceeded(_:)``/``handshakeFailed(_:)``.
///
/// The source IP is used only as a throttling key here, never as a trust input (invariant 3):
/// this type has no notion of a peer's certificate or SPKI at all, and
/// ``PeerAuthorizer/decide(spki:trustStore:window:)`` (E12-02) takes no address or admission
/// parameter, so nothing this actor decides can ever mark a peer trusted -- passing every cap
/// below grants no trust, and failing one never revokes any.
public actor ConnectionAdmission {

    /// Opaque per-connection handle, unique for the lifetime of one ``ConnectionAdmission``
    /// instance. Returned by ``accept(ipAddress:onHandshakeDeadline:)`` and threaded back through
    /// ``handshakeSucceeded(_:)``/``handshakeFailed(_:)`` so this actor never needs to hold a
    /// reference to the real connection.
    public struct ConnectionID: Hashable, Sendable {
        fileprivate let value: Int
    }

    /// SPEC.md §10: "Concurrent not-yet-Ready connections" caps.
    public static let totalPreAuthCap = 8
    public static let perIPPreAuthCap = 2
    /// SPEC.md §10: TLS handshake deadline, Mac side.
    public static let tlsHandshakeDeadline: Duration = .seconds(10)
    /// SPEC.md §10: "a source IP with >= 10 failed handshakes within a rolling 60 s window is
    /// refused for 60 s".
    public static let failureThreshold = 10
    public static let failureWindow: Duration = .seconds(60)
    public static let ipRefusalDuration: Duration = .seconds(60)

    public enum AdmissionDecision: Sendable, Equatable {
        case admitted(ConnectionID)
        case refused
    }

    private struct Slot {
        let ipAddress: String
        var deadlineTask: Task<Void, Never>?
    }

    private let clock: any Clock<Duration>
    private let totalPreAuthCap: Int
    private let perIPPreAuthCap: Int
    private var slots: [ConnectionID: Slot] = [:]
    private var perIPCounts: [String: Int] = [:]
    private var failureCounts: [String: Int] = [:]
    private var throttledIPs: Set<String> = []
    private var nextIDValue = 0

    /// `totalPreAuthCap`/`perIPPreAuthCap` default to the SPEC.md §10 values (``totalPreAuthCap``,
    /// ``perIPPreAuthCap``, the `static` properties above) and exist as `init` parameters, not
    /// hard-coded, purely so the *total*-cap behavior is independently exercisable over a real
    /// loopback socket without needing several real source addresses (`ListenerLoopbackTests`
    /// widens `perIPPreAuthCap` for exactly that; production callers never pass either).
    public init(
        clock: any Clock<Duration>,
        totalPreAuthCap: Int = ConnectionAdmission.totalPreAuthCap,
        perIPPreAuthCap: Int = ConnectionAdmission.perIPPreAuthCap
    ) {
        self.clock = clock
        self.totalPreAuthCap = totalPreAuthCap
        self.perIPPreAuthCap = perIPPreAuthCap
    }

    /// Consulted on every accept, before the TLS handshake starts (SPEC.md §10): refuses
    /// `ipAddress` outright while it is throttled, else refuses once ``totalPreAuthCap`` or
    /// ``perIPPreAuthCap`` is reached, else admits and starts racing ``tlsHandshakeDeadline``.
    ///
    /// - Parameters:
    ///   - ipAddress: The remote endpoint's host, used only to key the caps/throttle above --
    ///     never a trust input.
    ///   - onHandshakeDeadline: Called at most once, from this actor, if the connection is still
    ///     open ``tlsHandshakeDeadline`` after acceptance without the caller having reported an
    ///     outcome -- the caller's cue to actually cancel the real connection, since this actor
    ///     never touches sockets itself. The elapsed deadline itself already counts as a failed
    ///     handshake and frees the slot (SPEC.md §10's "failed handshake" definition explicitly
    ///     includes "an idle TCP connection that never sends a `ClientHello`... once its 10 s
    ///     deadline elapses"), so the caller need not separately report one.
    public func accept(
        ipAddress: String,
        onHandshakeDeadline: @escaping @Sendable () -> Void
    ) -> AdmissionDecision {
        guard !throttledIPs.contains(ipAddress) else { return .refused }
        guard slots.count < totalPreAuthCap else { return .refused }
        guard (perIPCounts[ipAddress] ?? 0) < perIPPreAuthCap else { return .refused }

        let id = ConnectionID(value: nextIDValue)
        nextIDValue += 1
        perIPCounts[ipAddress, default: 0] += 1

        let clock = clock
        let deadlineTask = Task { [weak self] in
            try? await clock.sleep(for: Self.tlsHandshakeDeadline)
            guard !Task.isCancelled, let self else { return }
            if await self.handshakeDeadlineElapsed(id: id) {
                onHandshakeDeadline()
            }
        }
        slots[id] = Slot(ipAddress: ipAddress, deadlineTask: deadlineTask)
        return .admitted(id)
    }

    /// The TLS handshake completed and the listener's own checks (ALPN, the E12-02 verify block)
    /// accepted it. Frees the pre-auth slot without counting a failure -- a successful handshake
    /// is never a "failed handshake" under SPEC.md §10, regardless of which trust decision the
    /// verify block reached (`.trusted` or `.pairingCandidate`).
    public func handshakeSucceeded(_ id: ConnectionID) {
        releaseSlot(id)
    }

    /// The handshake ended in any way SPEC.md §10 counts as a "failed handshake": the verify
    /// callback rejected the peer, the TLS handshake itself failed, or the TCP connection
    /// closed/reset before completing. Frees the pre-auth slot and counts one failure toward the
    /// per-IP throttle. A no-op if `id` was already released (e.g. its deadline already fired).
    public func handshakeFailed(_ id: ConnectionID) {
        guard let slot = releaseSlot(id) else { return }
        recordFailure(ipAddress: slot.ipAddress)
    }

    @discardableResult
    private func releaseSlot(_ id: ConnectionID) -> Slot? {
        guard let slot = slots.removeValue(forKey: id) else { return nil }
        slot.deadlineTask?.cancel()
        if let count = perIPCounts[slot.ipAddress] {
            if count <= 1 {
                perIPCounts.removeValue(forKey: slot.ipAddress)
            } else {
                perIPCounts[slot.ipAddress] = count - 1
            }
        }
        return slot
    }

    /// Fires once ``tlsHandshakeDeadline`` elapses for `id` without a reported outcome. Returns
    /// whether the caller's `onHandshakeDeadline` closure should actually run -- `false` if the
    /// connection already reported its own outcome first, racing this deadline.
    private func handshakeDeadlineElapsed(id: ConnectionID) -> Bool {
        guard let slot = releaseSlot(id) else { return false }
        recordFailure(ipAddress: slot.ipAddress)
        return true
    }

    /// Counts one failed handshake toward `ipAddress`'s rolling ``failureWindow``, refusing it for
    /// ``ipRefusalDuration`` once ``failureThreshold`` is reached. Each individual failure expires
    /// out of the rolling count on its own, independent of the refusal timer.
    private func recordFailure(ipAddress: String) {
        let newCount = (failureCounts[ipAddress] ?? 0) + 1
        failureCounts[ipAddress] = newCount

        let clock = clock
        Task { [weak self] in
            try? await clock.sleep(for: Self.failureWindow)
            await self?.expireFailure(ipAddress: ipAddress)
        }

        guard newCount >= Self.failureThreshold, !throttledIPs.contains(ipAddress) else { return }
        throttledIPs.insert(ipAddress)
        Task { [weak self] in
            try? await clock.sleep(for: Self.ipRefusalDuration)
            await self?.clearThrottle(ipAddress: ipAddress)
        }
    }

    private func expireFailure(ipAddress: String) {
        guard let count = failureCounts[ipAddress] else { return }
        if count <= 1 {
            failureCounts.removeValue(forKey: ipAddress)
        } else {
            failureCounts[ipAddress] = count - 1
        }
    }

    private func clearThrottle(ipAddress: String) {
        throttledIPs.remove(ipAddress)
    }
}
