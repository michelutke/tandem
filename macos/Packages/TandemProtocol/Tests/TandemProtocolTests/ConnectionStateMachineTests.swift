import Foundation
import Testing
import TandemTestSupport
@testable import TandemProtocol

/// E12-09: `ConnectionStateMachine`, the per-accepted-connection state machine (Android
/// counterpart: `ConnectionStateMachine`, E12-08; docs/protocol/SPEC.md
/// #handshake-and-tls-profile "Failure behavior", #errors-and-close-codes,
/// #timeouts-connection-limits-and-resource-caps; invariant 5). Exercised directly against the
/// actor's own `handle(_:)`/`state`, never against a real socket or TLS handshake -- this
/// package may not depend on `TandemTransport`.
@Suite("ConnectionStateMachine")
struct ConnectionStateMachineTests {
    @Test
    func connectionSm_incomingConnection_emitsAccepted() async {
        let machine = ConnectionStateMachine(clock: ManualTestClock())

        let accepted = await machine.handle(.incomingConnection)

        #expect(accepted)
        let state = await machine.state
        #expect(state == .accepted)
    }

    @Test
    func connectionSm_handshakeStarted_emitsTlsHandshaking() async {
        let machine = ConnectionStateMachine(clock: ManualTestClock())
        _ = await machine.handle(.incomingConnection)

        let accepted = await machine.handle(.handshakeStarted)

        #expect(accepted)
        let state = await machine.state
        #expect(state == .tlsHandshaking)
    }

    @Test
    func connectionSm_handshakeCompleted_emitsHelloExchange() async {
        let machine = ConnectionStateMachine(clock: ManualTestClock())
        _ = await machine.handle(.incomingConnection)
        _ = await machine.handle(.handshakeStarted)

        let accepted = await machine.handle(.handshakeCompleted)

        #expect(accepted)
        let state = await machine.state
        #expect(state == .helloExchange)
    }

    @Test
    func connectionSm_compatibleHelloReceived_emitsReady() async {
        let machine = ConnectionStateMachine(clock: ManualTestClock())
        _ = await machine.handle(.incomingConnection)
        _ = await machine.handle(.handshakeStarted)
        _ = await machine.handle(.handshakeCompleted)

        let accepted = await machine.handle(.compatibleHelloReceived)

        #expect(accepted)
        let state = await machine.state
        #expect(state == .ready)
    }

    @Test
    func connectionSm_handshakeErrorInAnyState_emitsFailedWithNonEmptyReason() async {
        // "Any state" here means any of the four non-terminal states this machine can be in once
        // a connection has been accepted (SPEC.md "Failure behavior": Failed is reachable from
        // any state on handshake/Hello failure).
        let statesReachedBy: [[ConnectionStateMachine.Event]] = [
            [.incomingConnection],
            [.incomingConnection, .handshakeStarted],
            [.incomingConnection, .handshakeStarted, .handshakeCompleted],
            [.incomingConnection, .handshakeStarted, .handshakeCompleted, .compatibleHelloReceived]
        ]

        for events in statesReachedBy {
            let machine = ConnectionStateMachine(clock: ManualTestClock())
            for event in events {
                _ = await machine.handle(event)
            }

            let accepted = await machine.handle(.handshakeError(.versionMismatch))

            #expect(accepted)
            let state = await machine.state
            #expect(state == .failed(.versionMismatch), "reached via \(events)")
        }
    }

    @Test
    func connectionSm_socketClosedWhileReady_emitsDisconnectedWithReason() async {
        let machine = ConnectionStateMachine(clock: ManualTestClock())
        _ = await machine.handle(.incomingConnection)
        _ = await machine.handle(.handshakeStarted)
        _ = await machine.handle(.handshakeCompleted)
        _ = await machine.handle(.compatibleHelloReceived)

        let accepted = await machine.handle(.socketClosed(reason: "peer reset"))

        #expect(accepted)
        let state = await machine.state
        #expect(state == .disconnected(reason: "peer reset"))
    }

    @Test
    func connectionSm_handshakeStartedWhileReady_rejectedStateUnchanged() async {
        let machine = ConnectionStateMachine(clock: ManualTestClock())
        _ = await machine.handle(.incomingConnection)
        _ = await machine.handle(.handshakeStarted)
        _ = await machine.handle(.handshakeCompleted)
        _ = await machine.handle(.compatibleHelloReceived)

        let accepted = await machine.handle(.handshakeStarted)

        #expect(!accepted, "an illegal event must be reported as rejected")
        let state = await machine.state
        #expect(state == .ready, "an illegal event must leave the state unchanged")
    }

    @Test
    func connectionSm_handshakeTimeoutElapsed_emitsFailedTimeout() async {
        let clock = ManualTestClock()
        let machine = ConnectionStateMachine(clock: clock)
        _ = await machine.handle(.incomingConnection)
        _ = await machine.handle(.handshakeStarted)
        for _ in 0..<10 { await Task.yield() } // let handle(_:) start racing the deadline

        clock.advance(by: ConnectionStateMachine.handshakeDeadline)
        for _ in 0..<10 { await Task.yield() } // let the deadline task resolve into the actor

        let state = await machine.state
        #expect(state == .failed(.protocolTimeout))
    }

    @Test
    func connectionSm_handshakeCompletedBeforeDeadline_neverEmitsTimeout() async {
        let clock = ManualTestClock()
        let machine = ConnectionStateMachine(clock: clock)
        _ = await machine.handle(.incomingConnection)
        _ = await machine.handle(.handshakeStarted)
        _ = await machine.handle(.handshakeCompleted)
        for _ in 0..<10 { await Task.yield() }

        clock.advance(by: ConnectionStateMachine.handshakeDeadline)
        for _ in 0..<10 { await Task.yield() }

        let state = await machine.state
        #expect(state == .helloExchange, "the deadline must be cancelled once the handshake completes")
    }

    @Test
    func connectionSm_states_publishesEveryAcceptedTransitionInOrder() async {
        let machine = ConnectionStateMachine(clock: ManualTestClock())
        var iterator = machine.states.makeAsyncIterator()

        _ = await machine.handle(.incomingConnection)
        _ = await machine.handle(.handshakeStarted)
        _ = await machine.handle(.handshakeCompleted)
        _ = await machine.handle(.compatibleHelloReceived)
        _ = await machine.handle(.socketClosed(reason: "peer reset"))

        var published: [ConnectionStateMachine.ConnectionState] = []
        for _ in 0..<6 {
            guard let next = await iterator.next() else { break }
            published.append(next)
        }

        #expect(published == [
            .disconnected(reason: nil),
            .accepted,
            .tlsHandshaking,
            .helloExchange,
            .ready,
            .disconnected(reason: "peer reset")
        ])
    }

    @Test
    func connectionSm_readyThenSocketClosed_emitsReadyThenDisconnectedMarkers() async {
        let markers = RecordingReconnectMarkers()
        let machine = ConnectionStateMachine(clock: ManualTestClock(), markers: markers)
        _ = await machine.handle(.incomingConnection)
        _ = await machine.handle(.handshakeStarted)
        _ = await machine.handle(.handshakeCompleted)
        _ = await machine.handle(.compatibleHelloReceived)
        _ = await machine.handle(.socketClosed(reason: "closed locally"))

        #expect(markers.events == ["ready", "disconnected"])
    }

    @Test
    func connectionSm_readyThenDeadPeerTimeout_emitsReadyThenDeadMarkers() async {
        let markers = RecordingReconnectMarkers()
        let machine = ConnectionStateMachine(clock: ManualTestClock(), markers: markers)
        _ = await machine.handle(.incomingConnection)
        _ = await machine.handle(.handshakeStarted)
        _ = await machine.handle(.handshakeCompleted)
        _ = await machine.handle(.compatibleHelloReceived)
        _ = await machine.handle(.deadPeerTimeout)

        #expect(markers.events == ["ready", "dead"])
    }
}

private final class RecordingReconnectMarkers: ReconnectMarkers, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var events: [String] { lock.withLock { recorded } }

    func disconnected() { lock.withLock { recorded.append("disconnected") } }
    func dead() { lock.withLock { recorded.append("dead") } }
    func ready() { lock.withLock { recorded.append("ready") } }
}
