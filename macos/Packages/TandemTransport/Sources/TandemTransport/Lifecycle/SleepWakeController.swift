import Foundation

/// Drives the Mac listener across sleep/wake (E20-10, `docs/protocol/SPEC.md` #heartbeat, PRD
/// F-3.4, UC-04): on ``SystemPowerEvent/willSleep`` stops ``ListenerControl`` -- which stops
/// accepting new connections and moves every open connection to `Disconnected`, E12-09 -- and on
/// ``SystemPowerEvent/didWake`` restarts it, so the phone's own reconnect flow (E20-06) finds the
/// listener ready promptly. A `didWake` with no prior `willSleep` is ignored: it never starts a
/// second listener alongside one that is already running. E22-08 observes the same
/// ``SystemPowerEvents`` stream for its own "Reconnecting..." menu bar state.
public actor SleepWakeController {

    private let powerEvents: any SystemPowerEvents
    private let listenerControl: any ListenerControl
    private var isSleeping = false
    private var observationTask: Task<Void, Never>?

    public init(powerEvents: any SystemPowerEvents, listenerControl: any ListenerControl) {
        self.powerEvents = powerEvents
        self.listenerControl = listenerControl
    }

    /// Begins observing ``SystemPowerEvents/events``. A second call replaces the prior observation
    /// task, so this is safe to call more than once.
    public func start() {
        observationTask?.cancel()
        let events = powerEvents.events
        observationTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                await self?.handle(event)
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    private func handle(_ event: SystemPowerEvent) async {
        switch event {
        case .willSleep:
            guard !isSleeping else { return }
            isSleeping = true
            await listenerControl.stop()
        case .didWake:
            guard isSleeping else { return }
            isSleeping = false
            try? await listenerControl.start()
        }
    }
}
