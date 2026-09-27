import Foundation
import Observation
import TandemProtocol

/// The menu bar's own presentation state (E22-01, PRD F-4.2, UC-01/UC-05): six states, each with
/// a distinct icon and exact label, mapping the paired session's ``ConnectionStateMachine``
/// (E12-09) transitions plus whether a peer is paired at all. Battery is a placeholder until E23
/// wires real telemetry; ``State/reconnecting`` is not reachable from any
/// ``ConnectionStateMachine/ConnectionState`` transition in this issue -- E22-08 drives it from
/// sleep/wake and network-restart events instead.
///
/// Presentation-independent -- no `SwiftUI` import -- unit-tested against the E12-12
/// `FakeTandemSession`'s own ``TandemSession/state`` stream (`@testable import TandemProtocol`,
/// the same seam `FakeTandemSessionTests` in `TandemProtocolTests` already uses).
/// ``MenuBarContentView`` is its SwiftUI presentation.
@MainActor
@Observable
final class MenuBarViewModel {
    /// One of the six states this issue's acceptance enumerates.
    enum State: Sendable, Equatable {
        case notPaired
        case connecting
        case connected(peerName: String)
        case reconnecting
        case disconnected
        case error
    }

    /// Battery placeholder text until E23 populates a real reading (backlog E22-01: "battery
    /// placeholder 'Battery: —'").
    static let batteryPlaceholder = "Battery: —"

    private(set) var state: State

    /// Threaded through now (E00-24 seam rule) so a later issue (E22-08: sleep/wake- and
    /// network-restart-driven "Reconnecting…" transitions, proved with `ManualTestClock`) doesn't
    /// need to change this initializer's shape. Not read yet -- this issue never times anything.
    private let clock: any Clock<Duration>

    /// `@ObservationIgnored` (not part of this view model's presented state) and
    /// `nonisolated(unsafe)`: `Task.cancel()` is safe from any thread, and `deinit` (unlike an
    /// actor's) is never itself main-actor-isolated on a `@MainActor` class.
    @ObservationIgnored
    private nonisolated(unsafe) var observationTask: Task<Void, Never>?

    /// - Parameters:
    ///   - stateStream: The paired session's own connection-state stream
    ///     (``TandemSession/state``), or `nil` if no peer is paired yet (UC-01) -- must be
    ///     non-nil exactly when `peerName` is non-nil.
    ///   - peerName: The paired peer's display name, or `nil` if none is paired.
    init(
        stateStream: AsyncStream<ConnectionStateMachine.ConnectionState>?,
        peerName: String?,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.clock = clock
        if let stateStream, let peerName {
            state = .connecting
            observe(stateStream, peerName: peerName)
        } else {
            state = .notPaired
        }
    }

    /// Test/preview-only constructor: sets ``state`` directly without observing any stream, so
    /// every ``State`` case -- including ``State/reconnecting``, unreachable from this issue's own
    /// mapping -- can be exercised for its icon/label.
    init(state: State, clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
        self.state = state
    }

    deinit {
        observationTask?.cancel()
    }

    /// The SF Symbol name for ``state``'s menu bar icon -- distinct per state (acceptance: "Each
    /// state ... maps to a distinct icon").
    var systemImageName: String {
        switch state {
        case .notPaired: return "person.crop.circle.badge.questionmark"
        case .connecting: return "circle.dotted"
        case .connected: return "checkmark.circle.fill"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        case .disconnected: return "circle.slash"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    /// ``state``'s exact label text (backlog E22-01 "UI strings (exact)").
    var label: String {
        switch state {
        case .notPaired: return "Not paired"
        case .connecting: return "Connecting…"
        case .connected(let peerName): return "Connected to \(peerName)"
        case .reconnecting: return "Reconnecting…"
        case .disconnected: return "Disconnected"
        case .error: return "Error"
        }
    }

    /// `true` while ``state`` is ``State/notPaired`` -- the dropdown then shows "Pair phone…"
    /// instead of the peer/battery rows (UC-01).
    var showsPairPhoneMenuItem: Bool {
        state == .notPaired
    }

    private func observe(_ stream: AsyncStream<ConnectionStateMachine.ConnectionState>, peerName: String) {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            for await connectionState in stream {
                guard !Task.isCancelled else { return }
                self?.apply(connectionState, peerName: peerName)
            }
        }
    }

    private func apply(_ connectionState: ConnectionStateMachine.ConnectionState, peerName: String) {
        state = Self.map(connectionState, peerName: peerName)
    }

    /// The pure reducer from a connection's own state to this menu bar's presentation state.
    static func map(_ connectionState: ConnectionStateMachine.ConnectionState, peerName: String) -> State {
        switch connectionState {
        case .disconnected:
            return .disconnected
        case .accepted, .tlsHandshaking, .helloExchange:
            return .connecting
        case .ready:
            return .connected(peerName: peerName)
        case .failed:
            return .error
        }
    }
}
