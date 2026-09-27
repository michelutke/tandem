import Foundation
import TandemProtocol

/// Mac half of the E01-07 liveness contract (`docs/protocol/SPEC.md` #heartbeat; E20-05) for one
/// connection -- the phone side is a separate issue (E20-15). After 15 s without sending any frame
/// on this connection (not only a `Heartbeat` -- any frame this side sends resets the timer), sends
/// exactly one `Heartbeat` on `CONTROL`. After 45 s without receiving any frame, moves
/// ``ConnectionStateMachine`` to ``ConnectionStateMachine/ConnectionState/dead`` and cancels the
/// connection. Never replies to a received `Heartbeat` -- this type has no logic that ever sends in
/// response to a receive event, only from its own idle-send timer, so there is no ping-pong loop.
///
/// Also enforces `docs/planning/decisions.md` D-61/D-66: any `CONTROL` frame received from the
/// peer (D-66: including a `Heartbeat`, reply or unsolicited -- D-61's own wording excludes
/// `Heartbeat`, but D-66 folds it back in to close the gap a compromised-but-authenticated phone
/// could otherwise flood through) past ``controlFrameCap`` within a rolling
/// ``controlFrameCapWindow`` closes the connection with `CloseCode.limitExceeded`.
///
/// One instance per connection, constructed once ``ByteStreamSession``/``ConnectionStateMachine``
/// reach `Ready` (``ListenerFactory``'s own wiring) -- unlike ``SleepWakeController``/
/// ``PathChangeController``, which each own a single process-wide OS event stream, every timer and
/// counter here is local to the one connection this instance was built for, so one connection
/// going dead (or flooding `CONTROL`) never touches another's. Every deadline is driven by an
/// injected `any Clock<Duration>` (E00-24 seam rule; `TandemTestSupport`'s `ManualTestClock` in
/// tests) rather than wall-clock time, exactly like ``ConnectionStateMachine``'s own handshake
/// deadline.
///
/// Send/receive activity comes from ``ChannelMultiplexer/sent``/``ChannelMultiplexer/received`` --
/// broadcast streams that report every frame on every channel without ever consuming a channel's
/// own ``ChannelMultiplexer/inbound(_:)`` stream, so observing them here never steals a frame some
/// other consumer (a feature channel's own reader, or a future `CONTROL` reader) would otherwise
/// see.
public actor HeartbeatController {
    /// SPEC.md #heartbeat: idle-send interval before the Mac sends an unsolicited `Heartbeat`.
    public static let sendIdleInterval: Duration = .seconds(15)
    /// SPEC.md #heartbeat: dead-peer threshold, either side.
    public static let deadPeerThreshold: Duration = .seconds(45)
    /// `docs/planning/decisions.md` D-61/D-66: `CONTROL` frames received, per session -- includes
    /// `Heartbeat`s per D-66.
    public static let controlFrameCap = 60
    public static let controlFrameCapWindow: Duration = .seconds(1)

    private let session: any TandemSession
    private let stateMachine: ConnectionStateMachine
    private let sentEvents: AsyncStream<Void>
    private let receivedEvents: AsyncStream<FrameArrival>
    private let clock: any Clock<Duration>
    private let cancelConnection: @Sendable () -> Void

    private var sendIdleTask: Task<Void, Never>?
    private var deadPeerTask: Task<Void, Never>?
    private var sentObserverTask: Task<Void, Never>?
    private var receivedObserverTask: Task<Void, Never>?
    private var controlFrameCount = 0
    private var stopped = false

    /// Incremented every time ``resetSendIdleTimer()`` actually (re)schedules ``sendIdleTask``.
    /// Not part of the public seam surface; exposed (via `@testable import`, matching
    /// `TandemTestSupport.ManualTestClock.pendingSleeperCountForTesting`'s own convention) so a
    /// test can deterministically wait for a reset to have been *called* before advancing a shared
    /// `ManualTestClock` further.
    private(set) var sendIdleResetCountForTesting = 0
    /// Same as ``sendIdleResetCountForTesting``, for ``resetDeadPeerTimer()``.
    private(set) var deadPeerResetCountForTesting = 0

    public init(
        session: any TandemSession,
        stateMachine: ConnectionStateMachine,
        sent: AsyncStream<Void>,
        received: AsyncStream<FrameArrival>,
        clock: any Clock<Duration>,
        cancelConnection: @escaping @Sendable () -> Void
    ) {
        self.session = session
        self.stateMachine = stateMachine
        self.sentEvents = sent
        self.receivedEvents = received
        self.clock = clock
        self.cancelConnection = cancelConnection
    }

    /// Starts every timer and both observation loops. A second call replaces the prior ones, so
    /// this is safe to call more than once (matches ``SleepWakeController``/``PathChangeController``).
    public func start() {
        stopped = false
        resetSendIdleTimer()
        resetDeadPeerTimer()

        sentObserverTask?.cancel()
        let sentEvents = sentEvents
        sentObserverTask = Task { [weak self] in
            for await _ in sentEvents {
                guard !Task.isCancelled else { return }
                await self?.resetSendIdleTimer()
            }
        }

        receivedObserverTask?.cancel()
        let receivedEvents = receivedEvents
        receivedObserverTask = Task { [weak self] in
            for await arrival in receivedEvents {
                guard !Task.isCancelled else { return }
                await self?.handleReceived(arrival)
            }
        }
    }

    /// Cancels every timer and both observation loops. Safe to call more than once, or without a
    /// prior ``start()``. Callers (``ListenerFactory``) call this once this connection's own
    /// `ChannelMultiplexer` closes, for any reason, so nothing here keeps running past that point.
    public func stop() {
        stopped = true
        sendIdleTask?.cancel()
        deadPeerTask?.cancel()
        sentObserverTask?.cancel()
        receivedObserverTask?.cancel()
    }

    deinit {
        sendIdleTask?.cancel()
        deadPeerTask?.cancel()
        sentObserverTask?.cancel()
        receivedObserverTask?.cancel()
    }

    private func resetSendIdleTimer() {
        guard !stopped else { return }
        sendIdleResetCountForTesting += 1
        sendIdleTask?.cancel()
        let clock = clock
        sendIdleTask = Task { [weak self] in
            try? await clock.sleep(for: HeartbeatController.sendIdleInterval)
            guard !Task.isCancelled else { return }
            await self?.sendIdleElapsed()
        }
    }

    /// 15 s elapsed without this connection sending any frame: sends exactly one `Heartbeat` on
    /// `CONTROL`. That send itself reaches ``ChannelMultiplexer/sent``, so the idle-send timer is
    /// restarted from here for the next occurrence -- never scheduled directly by this method.
    private func sendIdleElapsed() async {
        guard !stopped else { return }
        try? await session.send(.control, payload: .heartbeat(Tandem_V1_Heartbeat()))
    }

    private func resetDeadPeerTimer() {
        guard !stopped else { return }
        deadPeerResetCountForTesting += 1
        deadPeerTask?.cancel()
        let clock = clock
        deadPeerTask = Task { [weak self] in
            try? await clock.sleep(for: HeartbeatController.deadPeerThreshold)
            guard !Task.isCancelled else { return }
            await self?.deadPeerThresholdElapsed()
        }
    }

    /// 45 s elapsed without this connection receiving any frame: declares it dead and cancels it
    /// (SPEC.md #heartbeat "the Mac MUST treat the control connection as dead ... and MUST close
    /// its side"). A local, transport-liveness event -- ``ConnectionStateMachine/Event
    /// /deadPeerTimeout`` moves ``ConnectionStateMachine`` to its own `dead` state, never
    /// `failed(_:)` (SPEC.md: "not a close code").
    private func deadPeerThresholdElapsed() async {
        guard !stopped else { return }
        stop()
        await stateMachine.handle(.deadPeerTimeout)
        cancelConnection()
    }

    private func handleReceived(_ arrival: FrameArrival) async {
        guard !stopped else { return }
        resetDeadPeerTimer()

        // D-66: every Heartbeat the Mac receives (reply or unsolicited) counts toward the same
        // D-61 cap as non-Heartbeat CONTROL frames -- D-61's literal wording alone would let a
        // compromised-but-authenticated phone flood unsolicited Heartbeats without ever tripping
        // the cap.
        guard arrival.channel == .control else { return }
        controlFrameCount += 1
        if controlFrameCount > HeartbeatController.controlFrameCap {
            await controlFrameCapExceeded()
            return
        }

        let clock = clock
        Task { [weak self] in
            try? await clock.sleep(for: HeartbeatController.controlFrameCapWindow)
            await self?.expireControlFrame()
        }
    }

    private func expireControlFrame() {
        guard controlFrameCount > 0 else { return }
        controlFrameCount -= 1
    }

    /// D-61/D-66: the 61st `CONTROL` frame (`Heartbeat` or not) within a rolling 1 s window. Unlike dead-peer
    /// detection, this is a wire close code (`LIMIT_EXCEEDED`) -- reuses
    /// ``ConnectionStateMachine/Event/handshakeError(_:)``, which already transitions `Ready` to
    /// `failed(_:)` for exactly this "this connection failed with a given close code" purpose,
    /// regardless of its name.
    private func controlFrameCapExceeded() async {
        guard !stopped else { return }
        stop()
        await stateMachine.handle(.handshakeError(.limitExceeded))
        cancelConnection()
    }
}
