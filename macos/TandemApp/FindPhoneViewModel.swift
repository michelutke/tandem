import Observation
import TandemProtocol

/// Wires the menu bar's "Find Phone" quick action (E22-02 stub) to the STATUS channel's
/// `Ring`/`RingStop` messages (PRD F-4.4, docs/protocol/SPEC.md #status-channel, E23-01).
/// Selecting the action while idle sends one `Ring` and flips ``label`` to "Stop Ringing";
/// selecting it again sends one `RingStop{origin: mac}` and flips ``label`` back to "Find Phone".
/// A `RingStop` the phone itself sent (`origin: phone`) reverts ``label`` the same way, without
/// sending anything back.
///
/// Presentation-independent -- no `SwiftUI` import -- unit-tested against the E12-12
/// `FakeTandemSession`'s own STATUS stream and its recorded `sent` calls (`@testable import
/// TandemProtocol`), the same seam ``DeviceStatusViewModel`` already uses. ``QuickActionsView``
/// reads ``label`` directly and calls ``select()`` from its "Find Phone" button.
@MainActor
@Observable
final class FindPhoneViewModel {
    /// Whether a ring is currently believed active on the phone -- drives ``label``.
    private enum RingState {
        case idle
        case ringing

        /// The exact label text for this state (backlog E23-07 "UI strings (exact)").
        var label: String {
            switch self {
            case .idle: return "Find Phone"
            case .ringing: return "Stop Ringing"
            }
        }
    }

    /// "Find Phone" or "Stop Ringing" -- what ``QuickActionsView`` shows for this action.
    private(set) var label = RingState.idle.label

    private var ringState = RingState.idle
    private var session: (any TandemSession)?

    /// "Phone not connected." after a selection with no session; cleared by the next one.
    private(set) var statusText: String?

    @ObservationIgnored
    private nonisolated(unsafe) var observationTask: Task<Void, Never>?

    /// - Parameter session: The paired session to send `Ring`/`RingStop` on and observe `RingStop`
    ///   from, or `nil` if no peer is paired yet -- ``select()`` is then a no-op.
    init(session: (any TandemSession)?) {
        self.session = session
        if let session {
            observe(session)
        }
    }

    deinit {
        observationTask?.cancel()
    }

    /// Toggles the ring: idle -> sends exactly one `Ring`, becomes ``RingState/ringing``; ringing
    /// -> sends exactly one `RingStop{origin: mac}`, becomes ``RingState/idle``. No-op with no
    /// session.
    func select() {
        guard let session else {
            statusText = "Phone not connected."
            return
        }
        statusText = nil
        switch ringState {
        case .idle:
            ringState = .ringing
            label = ringState.label
            Task { try? await session.send(.status, payload: .ring(Tandem_V1_Ring())) }
        case .ringing:
            ringState = .idle
            label = ringState.label
            var ringStop = Tandem_V1_RingStop()
            ringStop.origin = .mac
            Task { try? await session.send(.status, payload: .ringStop(ringStop)) }
        }
    }

    /// Switches to the paired peer's current session (`nil` once it ends): the ring resets and the
    /// phone-originated `RingStop` observation moves to the new session.
    func sessionChanged(_ session: (any TandemSession)?) {
        observationTask?.cancel()
        observationTask = nil
        self.session = session
        ringState = .idle
        label = RingState.idle.label
        statusText = nil
        if let session { observe(session) }
    }

    /// Observes `session`'s STATUS channel for a phone-originated `RingStop` (a `Ring` this side
    /// itself sent is never echoed back, so no other payload on this channel needs handling here).
    private func observe(_ session: any TandemSession) {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            let stream = await session.receive(.status)
            for await frame in stream {
                guard !Task.isCancelled else { return }
                guard case .ringStop(let ringStop)? = frame.payload, ringStop.origin == .phone else { continue }
                self?.ringState = .idle
                self?.label = RingState.idle.label
            }
        }
    }
}
