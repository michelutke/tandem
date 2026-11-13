import Observation
import TandemProtocol

/// The Mac side of the F-4.2 Mirror quick action (E61-12, invariant 8): sends one `MirrorRequest`
/// on the CONTROL channel when the user clicks the action and nothing else -- no capture, no
/// media ticket, no input. A `MirrorDeclined` while ``State/waiting`` moves to ``State/declined``;
/// one the Mac did not solicit is ignored (SPEC "Mirror request").
@MainActor
@Observable
public final class MirrorRequestViewModel {
    public enum State: Sendable, Equatable {
        case idle
        case waiting
        case declined
        case notConnected
    }

    public private(set) var state = State.idle

    /// Display name of the paired phone, for the waiting copy; `nil` reads as "phone".
    public var peerName: String?

    /// Menu status line for ``state``, or `nil` while idle.
    public var statusText: String? {
        switch state {
        case .idle: return nil
        case .waiting: return waitingDetail
        case .declined: return "Declined. Nothing was shared."
        case .notConnected: return "Phone not connected."
        }
    }

    /// ui-spec mirror.waiting.
    public var waitingDetail: String {
        "Accept on \(peerName ?? "phone") to start."
    }

    private var session: (any TandemSession)?
    private let clock: any Clock<Duration>
    private let timeout: Duration

    @ObservationIgnored
    private nonisolated(unsafe) var observationTask: Task<Void, Never>?

    @ObservationIgnored
    private nonisolated(unsafe) var timeoutTask: Task<Void, Never>?

    /// - Parameter session: The paired session, or `nil` if no peer is paired -- ``request()`` is
    ///   then shows ``State/notConnected``.
    public init(
        session: (any TandemSession)?,
        peerName: String? = nil,
        clock: any Clock<Duration> = ContinuousClock(),
        timeout: Duration = .seconds(60)
    ) {
        self.session = session
        self.peerName = peerName
        self.clock = clock
        self.timeout = timeout
    }

    deinit {
        observationTask?.cancel()
        timeoutTask?.cancel()
    }

    /// Switches to `session` (the paired peer's next control session, or `nil` once it ends) and
    /// resumes observing it; a pending request is dropped.
    public func sessionChanged(_ session: (any TandemSession)?) async {
        observationTask?.cancel()
        observationTask = nil
        self.session = session
        resetRequest()
        await start()
    }

    /// Begins observing the CONTROL channel for `MirrorDeclined`; returns once subscribed.
    public func start() async {
        guard let session, observationTask == nil else { return }
        let stream = await session.receive(.control)
        observationTask = Task { [weak self] in
            for await frame in stream {
                guard !Task.isCancelled else { return }
                guard case .mirrorDeclined? = frame.payload else { continue }
                self?.mirrorDeclinedReceived()
            }
        }
    }

    /// Sends exactly one `MirrorRequest` unless one is already pending.
    public func request() {
        guard state != .waiting else { return }
        guard let session else {
            state = .notConnected
            return
        }
        state = .waiting
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self, clock, timeout] in
            try? await clock.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.requestTimedOut()
        }
        Task { try? await session.send(.control, payload: .mirrorRequest(Tandem_V1_MirrorRequest())) }
    }

    /// Dismisses the waiting or declined state; sends nothing.
    public func cancel() {
        resetRequest()
    }

    /// Back to idle once the mirror window opened or closed, so the action can be used again.
    public func resetRequest() {
        timeoutTask?.cancel()
        timeoutTask = nil
        state = .idle
    }

    private func requestTimedOut() {
        guard state == .waiting else { return }
        state = .idle
    }

    private func mirrorDeclinedReceived() {
        guard state == .waiting else { return }
        state = .declined
    }
}
