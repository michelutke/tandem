import Foundation
import Testing
import TandemProtocol
@testable import TandemTestSupport
@testable import TandemTransport

/// Test harness and polling helpers for `HeartbeatControllerTests`, split out to keep that file
/// within the file/type-length lint bounds -- see its own doc comment for the two `ManualTestClock`
/// ordering hazards these helpers exist to avoid.
extension HeartbeatControllerTests {

    /// Wires a `mac`/`peer` pair of `ByteStreamSession`s over one `InMemoryConnectionPair`,
    /// exactly as ``ListenerFactory``'s own `wireSession` does over a real `NWConnection` --
    /// except both `ConnectionStateMachine`s are driven straight to `Ready` here (no real TLS/
    /// `VersionHandshake`, out of scope for this controller). `mac`'s multiplexer is the one
    /// `HeartbeatController` observes; `peer` stands in for the phone.
    final class Harness: Sendable {
        let clock: ManualTestClock
        let mac: ByteStreamSession
        let peer: ByteStreamSession
        let controller: HeartbeatController
        let peerControlFrames: FrameCollector
        private let macStates: StateCollector
        private let cancelledBox: CancelledBox

        var macState: ConnectionStateMachine.ConnectionState? {
            get async { await macStates.latest }
        }

        var cancelled: Bool {
            get async { await cancelledBox.value }
        }

        private init(
            clock: ManualTestClock,
            mac: ByteStreamSession,
            peer: ByteStreamSession,
            controller: HeartbeatController,
            peerControlFrames: FrameCollector,
            macStates: StateCollector,
            cancelledBox: CancelledBox
        ) {
            self.clock = clock
            self.mac = mac
            self.peer = peer
            self.controller = controller
            self.peerControlFrames = peerControlFrames
            self.macStates = macStates
            self.cancelledBox = cancelledBox
        }

        static func make(clock: ManualTestClock = ManualTestClock()) async -> Harness {
            let pair = InMemoryConnectionPair()

            let macMultiplexer = ChannelMultiplexer(
                source: ByteStreamConnectionFrameSource(pair.endA),
                sink: pair.endA.send
            )
            let peerMultiplexer = ChannelMultiplexer(
                source: ByteStreamConnectionFrameSource(pair.endB),
                sink: pair.endB.send
            )
            await macMultiplexer.start()
            await peerMultiplexer.start()

            let macStateMachine = ConnectionStateMachine(clock: clock)
            let macStates = StateCollector()
            await macStates.collect(from: macStateMachine.states)
            await macStateMachine.handle(.incomingConnection)
            await macStateMachine.handle(.handshakeStarted)
            await macStateMachine.handle(.handshakeCompleted)
            await macStateMachine.handle(.compatibleHelloReceived)

            let peerStateMachine = ConnectionStateMachine(clock: clock)
            await peerStateMachine.handle(.incomingConnection)
            await peerStateMachine.handle(.handshakeStarted)
            await peerStateMachine.handle(.handshakeCompleted)
            await peerStateMachine.handle(.compatibleHelloReceived)

            let mac = ByteStreamSession(multiplexer: macMultiplexer, stateMachine: macStateMachine)
            let peer = ByteStreamSession(multiplexer: peerMultiplexer, stateMachine: peerStateMachine)

            let cancelledBox = CancelledBox()
            let controller = HeartbeatController(
                session: mac,
                stateMachine: macStateMachine,
                sent: macMultiplexer.sent,
                received: macMultiplexer.received,
                clock: clock,
                cancelConnection: { Task { await cancelledBox.markCancelled() } }
            )
            await controller.start()
            // See this file's own doc comment: `start()` only launches the two timer `Task`s: it
            // does not wait for them to actually reach `clock.sleep(for:)` and register. Block
            // here until they have, so this connection's very first `clock.advance(...)` can
            // never race ahead of them.
            _ = await waitForParkedSleepers(clock, count: clock.pendingSleeperCountForTesting + 2)

            let peerControlFrames = FrameCollector()
            let peerControlStream = await peer.receive(.control)
            await peerControlFrames.collect(from: peerControlStream)

            return Harness(
                clock: clock,
                mac: mac,
                peer: peer,
                controller: controller,
                peerControlFrames: peerControlFrames,
                macStates: macStates,
                cancelledBox: cancelledBox
            )
        }

        /// A fixed, generous real-time budget for scenarios that only assert a *negative*
        /// ("nothing must have happened yet") -- safe to under-wait here, since slower-than-usual
        /// scheduling can only make the assertion more conservative, never falsely trigger it.
        func settle(iterations: Int = 100) async {
            for _ in 0..<iterations {
                await Task.yield()
                await realDelay(milliseconds: 1)
            }
        }
    }

    /// Records every frame a `TandemSession/receive(_:)` stream yields, off the main test task, so
    /// a test can assert on it after polling lets the background collection loop run.
    actor FrameCollector {
        private(set) var frames: [InboundFrame] = []
        private var task: Task<Void, Never>?

        func collect(from stream: InboundFrameStream) {
            task = Task { [weak self] in
                for await frame in stream {
                    guard !Task.isCancelled else { return }
                    await self?.append(frame)
                }
            }
        }

        private func append(_ frame: InboundFrame) {
            frames.append(frame)
        }

        deinit {
            task?.cancel()
        }
    }

    /// Tracks the latest state a ``ConnectionStateMachine/states`` stream published, off the main
    /// test task -- ``ConnectionStateMachine/state`` itself is not `public` (only `handle(_:)` and
    /// `states` are, for callers outside `TandemProtocol`), so this is the one way a different
    /// module can observe it.
    actor StateCollector {
        private(set) var latest: ConnectionStateMachine.ConnectionState?
        private var task: Task<Void, Never>?

        func collect(from stream: AsyncStream<ConnectionStateMachine.ConnectionState>) {
            task = Task { [weak self] in
                for await state in stream {
                    guard !Task.isCancelled else { return }
                    await self?.update(state)
                }
            }
        }

        private func update(_ state: ConnectionStateMachine.ConnectionState) {
            latest = state
        }

        deinit {
            task?.cancel()
        }
    }

    actor CancelledBox {
        private(set) var value = false
        func markCancelled() { value = true }
    }
}

/// Polls `condition` until it is `true` or `timeout` elapses (real wall-clock time -- this is
/// purely a test-scheduling bound, unrelated to any `ManualTestClock` under test), returning the
/// final result either way so a failure still reports "false" rather than hanging.
func waitUntilTrue(
    timeout: Duration = .seconds(2),
    _ condition: () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while true {
        if await condition() { return true }
        if ContinuousClock.now >= deadline { return await condition() }
        await Task.yield()
        await realDelay(milliseconds: 1)
    }
}

/// A short real-time (not `ManualTestClock`) delay, for polling loops that need to give some
/// other unstructured `Task` a scheduling opportunity. Deliberately not `Task.sleep` (E00-24's
/// `injected_clock_only` lint rule bars it outside `TandemTestSupport`/`TandemApp`) -- matches
/// this package's own `ControlSessionRegistrationLoopbackTests`/`waitForRegistration(timeout:)`
/// convention of reaching for `DispatchQueue.global().asyncAfter` for exactly this purpose.
func realDelay(milliseconds: Int) async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
            continuation.resume()
        }
    }
}

/// Polls ``ManualTestClock/pendingSleeperCountForTesting`` (internal, `@testable`-only) until it
/// reaches at least `count`. See this file's own doc comment: a timer `Task` only registers with
/// `clock` once it actually reaches its own `clock.sleep(for:)` call, which can lag behind the
/// actor call that launched it by an arbitrary, unstructured-`Task`-scheduling amount.
func waitForParkedSleepers(
    _ clock: ManualTestClock,
    count: Int,
    timeout: Duration = .seconds(2)
) async -> Bool {
    await waitUntilTrue(timeout: timeout) { clock.pendingSleeperCountForTesting >= count }
}
