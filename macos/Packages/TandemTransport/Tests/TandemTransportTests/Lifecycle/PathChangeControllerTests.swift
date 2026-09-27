import Foundation
import Testing
import TandemTestSupport
@testable import TandemTransport

/// E20-11 (PRD F-3.4, UC-04): ``PathChangeController`` rebinds the listener exactly once per
/// network interface set change (Wi-Fi switch, VPN toggle) and never rebinds when the set is
/// unchanged -- against a recording ``ListenerControl`` fake (``FakeListenerControl``, reused from
/// `SleepWakeControllerTests`) and a ``NetworkPathSource`` fake this file drives directly. No real
/// `NWPathMonitor` anywhere in this file.
@Suite("PathChangeController")
struct PathChangeControllerTests {

    @Test
    func pathChangeController_interfaceSetChanged_listenerReboundOnce() async {
        let listenerControl = FakeListenerControl()
        let pathSource = FakeNetworkPathSource()
        let controller = PathChangeController(pathSource: pathSource, listenerControl: listenerControl)
        await controller.start()

        pathSource.send(NetworkPathSnapshot(interfaces: ["en0"]))
        await settle()
        pathSource.send(NetworkPathSnapshot(interfaces: ["en0", "utun0"]))
        await settle()

        #expect(listenerControl.stopCallCount == 1)
        #expect(listenerControl.startCallCount == 1)
    }

    @Test
    func pathChangeController_interfaceSetUnchanged_noRebind() async {
        let listenerControl = FakeListenerControl()
        let pathSource = FakeNetworkPathSource()
        let controller = PathChangeController(pathSource: pathSource, listenerControl: listenerControl)
        await controller.start()

        pathSource.send(NetworkPathSnapshot(interfaces: ["en0"]))
        await settle()
        pathSource.send(NetworkPathSnapshot(interfaces: ["en0"]))
        await settle()

        #expect(listenerControl.stopCallCount == 0)
        #expect(listenerControl.startCallCount == 0)
    }

    @Test
    func pathChangeController_sessionInterfaceStillPresent_sessionNotCancelled() async {
        let listenerControl = FakeListenerControl()
        try? await listenerControl.start()
        let pathSource = FakeNetworkPathSource()
        let controller = PathChangeController(pathSource: pathSource, listenerControl: listenerControl)
        await controller.start()

        // The listener's one open session lives on "en0", present in both snapshots below -- no
        // rebind ever happens, so `ListenerControl.stop()`'s documented contract (this package's
        // `ListenerControl.swift`) of cancelling every open connection is never invoked, and the
        // session on "en0" is left alone.
        pathSource.send(NetworkPathSnapshot(interfaces: ["en0"]))
        await settle()
        pathSource.send(NetworkPathSnapshot(interfaces: ["en0"]))
        await settle()

        #expect(listenerControl.stopCallCount == 0, "session on the still-present interface must not be cancelled")
        #expect(listenerControl.isRunning, "the listener and its open session must remain untouched")
    }

    /// Yields several times so the actor's background observation `Task` has a chance to consume
    /// snapshots already sent on ``FakeNetworkPathSource``, without an artificial wall-clock sleep.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

/// Recording ``NetworkPathSource`` fake driven directly by ``send(_:)``, standing in for a real
/// `NWPathMonitor` path stream in ``PathChangeControllerTests``.
final class FakeNetworkPathSource: NetworkPathSource, @unchecked Sendable {
    let paths: AsyncStream<NetworkPathSnapshot>
    private let continuation: AsyncStream<NetworkPathSnapshot>.Continuation

    init() {
        (paths, continuation) = AsyncStream<NetworkPathSnapshot>.makeStream()
    }

    func send(_ snapshot: NetworkPathSnapshot) {
        continuation.yield(snapshot)
    }
}
