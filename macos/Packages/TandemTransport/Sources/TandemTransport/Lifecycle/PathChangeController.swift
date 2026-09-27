import Foundation

/// Rebinds the Mac listener when the machine's network interface set changes (E20-11, PRD F-3.4,
/// UC-04): Wi-Fi switch, VPN toggle. Compares each ``NetworkPathSource`` snapshot's interface set
/// against the last one seen -- an unchanged set (e.g. the same Wi-Fi adapter handed a new IP by
/// its router) never rebinds, and the very first snapshot only seeds the baseline without
/// rebinding. A changed set stops and restarts ``ListenerControl`` exactly once, same protocol
/// ``SleepWakeController`` (E20-10) drives; the shared production adapter is what actually cancels
/// open connections on ``ListenerControl/stop()`` -- this controller has no notion of which
/// connection lives on which interface, so a session on an interface that is still present after
/// the change is left alone precisely because no rebind (and so no `stop()`) ever happens for it.
public actor PathChangeController {

    private let pathSource: any NetworkPathSource
    private let listenerControl: any ListenerControl
    private var lastInterfaces: Set<String>?
    private var observationTask: Task<Void, Never>?

    public init(pathSource: any NetworkPathSource, listenerControl: any ListenerControl) {
        self.pathSource = pathSource
        self.listenerControl = listenerControl
    }

    /// Begins observing ``NetworkPathSource/paths``. A second call replaces the prior observation
    /// task, so this is safe to call more than once.
    public func start() {
        observationTask?.cancel()
        let paths = pathSource.paths
        observationTask = Task { [weak self] in
            for await snapshot in paths {
                guard !Task.isCancelled else { return }
                await self?.handle(snapshot)
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    private func handle(_ snapshot: NetworkPathSnapshot) async {
        defer { lastInterfaces = snapshot.interfaces }
        guard let lastInterfaces, lastInterfaces != snapshot.interfaces else { return }
        await listenerControl.stop()
        try? await listenerControl.start()
    }
}
