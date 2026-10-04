import Foundation
import Network
import Testing
@testable import TandemTransport

/// E60-03: the media connection is accepted by the same single NWListener as the control
/// connection, over real TLS on localhost with a pinned peer.
@Suite("Media acceptor (hosted loopback)", .serialized)
struct MediaAcceptorLoopbackTests {
    private static let media = MediaFrameFixtures.validHelloFrame

    @Test(.timeLimit(.minutes(1)))
    func mediaAcceptor_validTicketOverLoopbackMtls_bindsToOriginatingSession() async throws {
        let harness = try await MediaLoopbackHarness()
        defer { harness.cleanup() }

        let client = try await harness.connectClient()
        try await client.send(Self.media)

        #expect(await Self.firstEvents(harness, count: 1) == [.bound(harness.validator.sessionID)])
    }

    @Test(.timeLimit(.minutes(1)))
    func mediaAcceptor_reusedTicketOverLoopbackMtls_closedWithZeroFramesDispatched() async throws {
        let bound = BindingCounter()
        let harness = try await MediaLoopbackHarness(onBound: { bound.increment() })
        defer { harness.cleanup() }

        let first = try await harness.connectClient()
        try await first.send(Self.media)
        #expect(await Self.firstEvents(harness, count: 1) == [.bound(harness.validator.sessionID)])

        let second = try await harness.connectClient()
        try await second.send(Self.media + Data(repeating: 0xEE, count: 64))

        #expect(await harness.waitForServerClose(second))
        #expect(await Self.firstEvents(harness, count: 1) == [.ticketRejected(.consumed)])
        #expect(bound.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func mediaAcceptor_duringActiveMirror_exactlyOneListeningSocket() async throws {
        let harness = try await MediaLoopbackHarness()
        defer { harness.cleanup() }

        let control = try await harness.openControlSession()
        let media = try await harness.connectClient()
        try await media.send(Self.media)
        #expect(await Self.firstEvents(harness, count: 1) == [.bound(harness.validator.sessionID)])

        let sockets = try Self.sockets(on: harness.port)
        let listening = sockets.filter { $0.contains("(LISTEN)") }
        let established = sockets.filter { $0.contains("(ESTABLISHED)") }

        #expect(listening.count == 1)
        #expect(established.count == 4)
        _ = control
    }

    /// This process's TCP sockets on `port`; each loopback connection shows up once per end. Other
    /// suites' listeners share the process, so only the sockets on this harness's port are inspected.
    private static func sockets(on port: NWEndpoint.Port) throws -> [String] {
        let output = try run(
            "/usr/sbin/lsof",
            ["-a", "-p", String(ProcessInfo.processInfo.processIdentifier), "-iTCP:\(port.rawValue)", "-P", "-n"]
        )
        return output.split(separator: "\n").map(String.init)
    }

    private static func firstEvents(_ harness: MediaLoopbackHarness, count: Int) async -> [MediaAcceptorEvent] {
        var events: [MediaAcceptorEvent] = []
        for await event in harness.acceptor.events {
            events.append(event)
            if events.count == count { break }
        }
        return events
    }
}

final class BindingCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}
