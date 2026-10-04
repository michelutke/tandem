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
    }

    public private(set) var state = State.idle

    /// Menu status line for ``state``, or `nil` while idle.
    public var statusText: String? {
        switch state {
        case .idle: return nil
        case .waiting: return "Accept on phone to start."
        case .declined: return "Mirroring declined on phone"
        }
    }

    private let session: (any TandemSession)?

    @ObservationIgnored
    private nonisolated(unsafe) var observationTask: Task<Void, Never>?

    /// - Parameter session: The paired session, or `nil` if no peer is paired -- ``request()`` is
    ///   then a no-op.
    public init(session: (any TandemSession)?) {
        self.session = session
    }

    deinit {
        observationTask?.cancel()
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
        guard let session, state != .waiting else { return }
        state = .waiting
        Task { try? await session.send(.control, payload: .mirrorRequest(Tandem_V1_MirrorRequest())) }
    }

    /// Dismisses the waiting or declined state; sends nothing.
    public func cancel() {
        state = .idle
    }

    private func mirrorDeclinedReceived() {
        guard state == .waiting else { return }
        state = .declined
    }
}
