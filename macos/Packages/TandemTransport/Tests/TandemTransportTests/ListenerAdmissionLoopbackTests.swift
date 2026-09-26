import Foundation
import Network
import Security
import Testing
import TandemCrypto
import TandemProtocol
@testable import TandemTransport

/// `ConnectionAdmission` (E12-18) wired into a real `NWListener`/`NWConnection` loopback --
/// pre-auth caps and the TLS handshake deadline, over real sockets rather than the pure actor
/// tests in `ConnectionAdmissionTests`. An `extension` of `ListenerLoopbackTests`, not a separate
/// `@Suite`, purely to stay under that file's SwiftLint file/type-length limits: these tests still
/// need `ListenerLoopbackTests`'s own `.serialized` trait, since
/// `listener_running_exactlyOneListeningTcpSocket` asserts there is exactly one listening socket
/// in the whole process and would otherwise race a listener this extension opens concurrently.
extension ListenerLoopbackTests {

    @Test(.timeLimit(.minutes(1)))
    func listener_loopbackStalledTcpConnection_closedWithin11s() async throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }

        let listener = try Self.makeAdmissionServerListener(identity: try serverKeychain.makeSecIdentity())
        defer { listener.cancel() }
        let port = try await Self.waitForAdmissionListenerPort(listener)

        // A bare TCP connection that never speaks TLS at all -- never sends a `ClientHello` --
        // is the "idle TCP connection" SPEC.md §10's failed-handshake definition names explicitly.
        // It must still be closed once the 10 s TLS handshake deadline (E12-18) elapses.
        let connection = Self.makePlainTcpConnection(port: port)
        defer { connection.cancel() }
        connection.start(queue: .global())

        let closed = await Self.waitForAdmissionReceiveEOFOrError(connection, timeout: 11)
        #expect(closed)
    }

    @Test(.timeLimit(.minutes(1)))
    func listener_tenIdleLoopbackConnections_ninthAndTenthClosedOnAccept() async throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }

        // A real 5-distinct-source loopback burst needs the `127.0.0.2..127.0.0.9` aliases the
        // E15-15/E15-20 CI harness sets up on the runner (`docs/planning/backlog/phase-1.yaml`,
        // E12-18's own note) -- unavailable, and not appropriate to require, in a plain `swift
        // test` run. So this test isolates the *total* 8-connection cap specifically: it widens
        // `perIPPreAuthCap` (an `init` parameter precisely for this, see ``ConnectionAdmission``)
        // to a value ten idle connections from the single real source (127.0.0.1) can never
        // reach, leaving ``ConnectionAdmission/totalPreAuthCap`` (still its real SPEC.md §10
        // default, 8) as the only cap this burst can hit -- the per-IP cap itself is already
        // covered end-to-end by `ConnectionAdmissionTests.connectionAdmission_thirdPreAuthFromSameIp_refused`.
        let admission = ConnectionAdmission(clock: ContinuousClock(), perIPPreAuthCap: 10)
        let listener = try Self.makeAdmissionServerListener(
            identity: try serverKeychain.makeSecIdentity(),
            admission: admission
        )
        defer { listener.cancel() }
        let port = try await Self.waitForAdmissionListenerPort(listener)

        // Connect strictly one at a time, each only after the previous has actually reached the
        // TCP-level `.ready` state, so the listener's accepts -- and therefore
        // `ConnectionAdmission`'s admit/refuse decisions -- happen in this same order (SPEC.md
        // §10: "Concurrent not-yet-Ready connections... <= 8 total").
        var connections: [NWConnection] = []
        defer { for connection in connections { connection.cancel() } }
        for index in 0..<10 {
            let observer = ConnectionObserver()
            let connection = Self.makePlainTcpConnection(port: port)
            observer.attach(to: connection)
            connection.start(queue: .global())
            let reachedReady = await observer.waitForReady(timeout: 5)
            #expect(reachedReady, "connection \(index) should reach TCP-level ready")
            connections.append(connection)
        }

        #expect(connections.count == 10)

        // The 9th and 10th are refused on accept -- before any TLS handshake -- so they close
        // almost immediately, well before the 10 s handshake deadline that (eventually) closes
        // the first 8.
        for index in 8..<10 {
            let closed = await Self.waitForAdmissionReceiveEOFOrError(connections[index], timeout: 3)
            #expect(closed, "connection \(index) should have been refused on accept")
        }

        for index in 0..<8 {
            let closed = await Self.waitForAdmissionReceiveEOFOrError(connections[index], timeout: 0.5)
            #expect(!closed, "connection \(index) should not yet be closed (admitted, pre-auth budget available)")
        }
    }

    // MARK: - Harness (duplicated from `ListenerLoopbackTests.swift`'s own `private` copies --
    // `private` members of a type aren't visible from an `extension` in another file)

    private static func makeAdmissionServerListener(
        identity: SecIdentity,
        admission: ConnectionAdmission = ConnectionAdmission(clock: ContinuousClock())
    ) throws -> NWListener {
        try NWListenerFactory(sessionRegistry: ControlSessionRegistry(), decisionCorrelator: PeerDecisionCorrelator()).makeListener(
            identity: identity,
            port: .any,
            verify: { _, _, complete in complete(true) },
            admission: admission
        )
    }

    private static func waitForAdmissionListenerPort(_ listener: NWListener) async throws -> NWEndpoint.Port {
        let resumeGuard = AdmissionResumeGuard()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard resumeGuard.tryResume() else { return }
                    guard let port = listener.port else {
                        continuation.resume(throwing: ListenerLoopbackTestError.noPort)
                        return
                    }
                    continuation.resume(returning: port)
                case .failed(let error):
                    guard resumeGuard.tryResume() else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .global())
        }
    }

    private static func waitForAdmissionReceiveEOFOrError(
        _ connection: NWConnection,
        timeout: TimeInterval
    ) async -> Bool {
        let resumeGuard = AdmissionResumeGuard()
        return await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, isComplete, error in
                guard resumeGuard.tryResume() else { return }
                continuation.resume(returning: isComplete || error != nil)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard resumeGuard.tryResume() else { return }
                continuation.resume(returning: false)
            }
        }
    }

    /// A bare TCP connection to the listener that never negotiates TLS at all -- no
    /// `NWProtocolTLS.Options` in its parameters, so it never sends a `ClientHello`. Used to
    /// exercise the pre-auth caps and TLS handshake deadline against connections that never get
    /// far enough to reach a TLS-specific rejection.
    private static func makePlainTcpConnection(port: NWEndpoint.Port) -> NWConnection {
        NWConnection(host: "127.0.0.1", port: port, using: .tcp)
    }
}

/// Lock-protected "resume this continuation exactly once" latch -- duplicated from
/// `ListenerLoopbackTests.swift`'s own file-scoped `ResumeGuard` (not visible from this file).
private final class AdmissionResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }
}
