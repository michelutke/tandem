import Foundation
import Observation
import TandemProtocol
import TandemTransport

/// The menu bar's own presentation state (E22-01, PRD F-4.2, UC-01/UC-05): six states, each with
/// a distinct icon and exact label, mapping the paired session's ``ConnectionStateMachine``
/// (E12-09) transitions plus whether a peer is paired at all. Battery is a placeholder until E23
/// wires real telemetry; ``State/reconnecting`` is never reached from a
/// ``ConnectionStateMachine/ConnectionState`` transition -- E22-08 drives it instead from the same
/// ``SystemPowerEvents`` (E20-10) sleep/wake stream and ``NetworkPathSource`` (E20-11)
/// network-restart stream ``SleepWakeController``/``PathChangeController`` observe to rebind the
/// listener, so the label never freezes on the last known state across either window.
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

    @ObservationIgnored
    private var peerName: String?
    @ObservationIgnored
    private var lastConnectionState: ConnectionStateMachine.ConnectionState?

    /// Threaded through now (E00-24 seam rule); not read directly by this view model -- E22-08's
    /// own "within 1 s" acceptance is proved the same way every other issue's own "publishes within
    /// 1 s" case already is, a yield-bounded loop rather than a wall-clock deadline, so callers only
    /// need this parameter to plug in a ``ManualTestClock`` for their own tests.
    private let clock: any Clock<Duration>

    /// `@ObservationIgnored` (not part of this view model's presented state) and
    /// `nonisolated(unsafe)`: `Task.cancel()` is safe from any thread, and `deinit` (unlike an
    /// actor's) is never itself main-actor-isolated on a `@MainActor` class.
    @ObservationIgnored
    private nonisolated(unsafe) var observationTask: Task<Void, Never>?

    /// E22-08: mirrors ``SleepWakeController``'s own `observationTask`/`isSleeping` pair -- a
    /// `didWake` with no prior `willSleep` is ignored, same guard, so this never overrides ``state``
    /// on a stray event.
    @ObservationIgnored
    private nonisolated(unsafe) var powerObservationTask: Task<Void, Never>?
    @ObservationIgnored
    private var isSleeping = false

    /// E22-08: mirrors ``PathChangeController``'s own `observationTask`/`lastInterfaces` pair -- the
    /// very first snapshot only seeds the baseline (never flips ``state``), same as that controller
    /// never rebinding on the first snapshot it sees.
    @ObservationIgnored
    private nonisolated(unsafe) var pathObservationTask: Task<Void, Never>?
    @ObservationIgnored
    private var lastInterfaces: Set<String>?

    /// - Parameters:
    ///   - stateStream: The paired session's own connection-state stream
    ///     (``TandemSession/state``), or `nil` if none is available. May be non-nil while `peerName`
    ///     is `nil`; ``updatePeerName(_:)`` then picks up a peer paired after launch.
    ///   - peerName: The paired peer's display name, or `nil` if none is paired.
    ///   - powerEvents: The Mac's own sleep/wake stream (E20-10), or `nil` to observe none -- only
    ///     ever observed when a session is paired; there is nothing to reconnect otherwise.
    ///   - pathSource: The Mac's own network-interface-change stream (E20-11), or `nil` to observe
    ///     none -- same pairing gate as `powerEvents`.
    init(
        stateStream: AsyncStream<ConnectionStateMachine.ConnectionState>?,
        peerName: String?,
        clock: any Clock<Duration> = ContinuousClock(),
        powerEvents: (any SystemPowerEvents)? = nil,
        pathSource: (any NetworkPathSource)? = nil
    ) {
        self.clock = clock
        self.peerName = peerName
        state = peerName == nil ? .notPaired : .connecting
        if let stateStream {
            observe(stateStream)
        }
        if peerName != nil {
            if let powerEvents {
                observePower(powerEvents)
            }
            if let pathSource {
                observePath(pathSource)
            }
        }
    }

    /// Test/preview-only constructor: sets ``state`` directly without observing any stream, so
    /// every ``State`` case -- including ``State/reconnecting`` -- can be exercised for its
    /// icon/label without a sleep/wake or network-path event.
    init(state: State, clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
        self.state = state
    }

    deinit {
        observationTask?.cancel()
        powerObservationTask?.cancel()
        pathObservationTask?.cancel()
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

    /// Re-syncs ``state`` after the paired peer changed (pairing commit or unpair): `nil` drops to
    /// ``State/notPaired``; a newly paired name resumes from the latest forwarded connection state.
    func updatePeerName(_ newName: String?) {
        guard newName != peerName else { return }
        peerName = newName
        guard let newName else {
            state = .notPaired
            return
        }
        state = lastConnectionState.map { Self.map($0, peerName: newName) } ?? .connecting
    }

    private func observe(_ stream: AsyncStream<ConnectionStateMachine.ConnectionState>) {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            for await connectionState in stream {
                guard !Task.isCancelled else { return }
                self?.apply(connectionState)
            }
        }
    }

    private func apply(_ connectionState: ConnectionStateMachine.ConnectionState) {
        lastConnectionState = connectionState
        guard let peerName else { return }
        state = Self.map(connectionState, peerName: peerName)
    }

    /// E22-08: mirrors ``SleepWakeController/start()``'s own observation loop over the same
    /// ``SystemPowerEvents`` stream.
    private func observePower(_ powerEvents: any SystemPowerEvents) {
        powerObservationTask?.cancel()
        let events = powerEvents.events
        powerObservationTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                self?.applyPower(event)
            }
        }
    }

    /// Mirrors ``SleepWakeController/handle(_:)``'s own `isSleeping` guard: a `didWake` with no
    /// prior `willSleep` is ignored, so this never overrides ``state`` on a stray event. Unlike
    /// that controller, `willSleep` itself never changes ``state`` -- only `didWake` does, dropping
    /// it into ``State/reconnecting`` until the session's own state stream reaches `.ready` again
    /// (this issue's acceptance).
    private func applyPower(_ event: SystemPowerEvent) {
        switch event {
        case .willSleep:
            guard !isSleeping else { return }
            isSleeping = true
        case .didWake:
            guard isSleeping else { return }
            isSleeping = false
            state = .reconnecting
        }
    }

    /// E22-08: mirrors ``PathChangeController/start()``'s own observation loop over the same
    /// ``NetworkPathSource`` stream.
    private func observePath(_ pathSource: any NetworkPathSource) {
        pathObservationTask?.cancel()
        let paths = pathSource.paths
        pathObservationTask = Task { [weak self] in
            for await snapshot in paths {
                guard !Task.isCancelled else { return }
                self?.applyPath(snapshot)
            }
        }
    }

    /// Mirrors ``PathChangeController/handle(_:)``'s own `lastInterfaces` comparison: the very
    /// first snapshot only seeds the baseline, and an unchanged interface set never re-flips
    /// ``state``.
    private func applyPath(_ snapshot: NetworkPathSnapshot) {
        defer { lastInterfaces = snapshot.interfaces }
        guard let lastInterfaces, lastInterfaces != snapshot.interfaces else { return }
        state = .reconnecting
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
        case .dead:
            // E20-05's dead-peer detection is "a local, transport-liveness event, not a close
            // code" (docs/protocol/SPEC.md #heartbeat) -- presented the same as any other
            // disconnection, never as `.error`. A future issue may map this to `.reconnecting`
            // once something here actually redials (E22-08).
            return .disconnected
        }
    }
}
