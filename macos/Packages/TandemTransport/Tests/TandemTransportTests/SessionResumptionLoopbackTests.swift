import Foundation
import Network
import Security
import Testing
import TandemProtocol
@testable import TandemTransport

/// E12-03: `NWListenerFactory` explicitly disables TLS session-ticket issuance
/// (`sec_protocol_options_set_tls_tickets_enabled(false)`) and resumption
/// (`sec_protocol_options_set_tls_resumption_enabled(false)`), so a client willing to resume never
/// gets the chance to -- every connection runs a full handshake -- and 0-RTT/early data, which
/// requires a PSK from a previously issued ticket, is never possible either. Real
/// Network.framework/Security.framework behaviour via `TemporaryKeychain` (E10-07b, D-75); no
/// login keychain.
///
/// These tests cannot themselves distinguish "no ticket was ever issued" from "a ticket was issued
/// but early data still isn't accepted": spike E03-01 §6 observed 0 of 10 tickets even with
/// `sec_protocol_options_set_tls_tickets_enabled(true)` once client-certificate auth is in play, and
/// there is no public Network.framework/Security.framework API to force-inspect ticket issuance or
/// early-data offer/accept independently of that. `sec_protocol_metadata_get_early_data_accepted` is
/// the only observable here, so a listener that (incorrectly) left resumption on could still pass
/// this suite if the client simply never got a ticket to offer. The real gate against that gap is
/// E15-11's `tools/pcap-audit` (`docs/protocol/SPEC.md` D-19/D-20 wire-level checks) run against a
/// captured handshake -- these hosted tests only assert the two public settings this type controls,
/// never a full guarantee that no ticket-bearing session could ever be resumed in practice.
@Suite("Session resumption disabled (hosted)", .serialized)
struct SessionResumptionLoopbackTests {

    @Test(.timeLimit(.minutes(1)))
    func listener_secondConnectionSameClient_verifyBlockInvokedAgain() async throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }
        let clientKeychain = try TemporaryKeychain()
        defer { clientKeychain.cleanup() }

        let verifyInvocationCount = InvocationCounter()
        let listener = try NWListenerFactory(
     sessionRegistry: ControlSessionRegistry(),
     decisionCorrelator: PeerDecisionCorrelator()
 ).makeListener(
            identity: try serverKeychain.makeSecIdentity(),
            port: .any,
            verify: { _, _, complete in
                verifyInvocationCount.increment()
                complete(true)
            },
            admission: ConnectionAdmission(clock: ContinuousClock())
        )
        defer { listener.cancel() }
        let port = try await Self.waitForListenerPort(listener)

        let clientOptions = Self.makeResumptionWillingClientOptions(
            identity: try clientKeychain.makeSecIdentity()
        )

        let first = try await Self.connectAndWaitForReady(port: port, options: clientOptions)
        first.cancel()
        let second = try await Self.connectAndWaitForReady(port: port, options: clientOptions)
        second.cancel()

        // The client's own `.ready` only depends on completing its side of the handshake; the
        // server's verify block -- which must itself run and call `complete(true)` before the
        // server sends its final handshake flight -- can still be a beat behind on the wall
        // clock, so wait for it rather than reading `.value` the instant `.ready` fires.
        let sawBothInvocations = await verifyInvocationCount.waitForCount(2, timeout: 5)
        #expect(sawBothInvocations)
        #expect(verifyInvocationCount.value == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func listener_clientEarlyDataEnabled_earlyDataNotAccepted() async throws {
        let serverKeychain = try TemporaryKeychain()
        defer { serverKeychain.cleanup() }
        let clientKeychain = try TemporaryKeychain()
        defer { clientKeychain.cleanup() }

        let listener = try NWListenerFactory(
     sessionRegistry: ControlSessionRegistry(),
     decisionCorrelator: PeerDecisionCorrelator()
 ).makeListener(
            identity: try serverKeychain.makeSecIdentity(),
            port: .any,
            verify: { _, _, complete in complete(true) },
            admission: ConnectionAdmission(clock: ContinuousClock())
        )
        defer { listener.cancel() }
        let port = try await Self.waitForListenerPort(listener)

        let clientOptions = Self.makeResumptionWillingClientOptions(
            identity: try clientKeychain.makeSecIdentity()
        )

        // First connection: nothing to resume from yet -- the server never issues a ticket for
        // this (or any) connection either way (E12-03).
        let first = try await Self.connectAndWaitForReady(port: port, options: clientOptions)
        first.cancel()

        // Second connection: this is where a TLS 1.3 client would offer 0-RTT early data, had the
        // first connection's (never-sent) ticket supported it.
        let second = try await Self.connectAndWaitForReady(port: port, options: clientOptions)
        defer { second.cancel() }

        let rawMetadata = second.metadata(definition: NWProtocolTLS.definition)
        let metadata = try #require(rawMetadata as? NWProtocolTLS.Metadata)
        #expect(sec_protocol_metadata_get_early_data_accepted(metadata.securityProtocolMetadata) == false)
    }

    // MARK: - Harness

    private static func makeResumptionWillingClientOptions(identity: SecIdentity) -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        let sec = options.securityProtocolOptions

        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv13)
        if let secIdentity = sec_identity_create(identity) {
            sec_protocol_options_set_local_identity(sec, secIdentity)
        }
        sec_protocol_options_add_tls_application_protocol(sec, tandemALPN)
        // Willing, not forcing: whether resumption/early data ever actually happen is entirely
        // the server's call (E12-03) -- these only ensure the client never itself declines them.
        sec_protocol_options_set_tls_tickets_enabled(sec, true)
        sec_protocol_options_set_tls_resumption_enabled(sec, true)
        sec_protocol_options_set_verify_block(sec, { _, _, complete in complete(true) }, .global())
        return options
    }

    @discardableResult
    private static func connectAndWaitForReady(
        port: NWEndpoint.Port,
        options: NWProtocolTLS.Options
    ) async throws -> NWConnection {
        let parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(host: "127.0.0.1", port: port, using: parameters)
        let observer = ConnectionObserver()
        observer.attach(to: connection)
        connection.start(queue: .global())

        guard await observer.waitForReady(timeout: 5) else {
            connection.cancel()
            throw SessionResumptionLoopbackTestError.neverReady
        }
        return connection
    }

    private static func waitForListenerPort(_ listener: NWListener) async throws -> NWEndpoint.Port {
        let resumeGuard = ResumeGuard()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard resumeGuard.tryResume() else { return }
                    guard let port = listener.port else {
                        continuation.resume(throwing: SessionResumptionLoopbackTestError.noPort)
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
}

private enum SessionResumptionLoopbackTestError: Error {
    case noPort
    case neverReady
}

/// Lock-protected invocation counter for the server verify block (`Sendable`, since the block
/// runs on `.global()`). ``waitForCount(_:timeout:)`` lets a caller wait for a bounded deadline
/// rather than racing the verify block's own completion: the client's `.ready` and the server's
/// verify-block completion are observed on independent queues, so nothing here guarantees the
/// latter has already run purely because the former has.
private final class InvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private struct Waiter {
        let target: Int
        let resumeGuard: ResumeGuard
        let continuation: CheckedContinuation<Void, Never>
    }

    private var waiter: Waiter?

    func increment() {
        lock.lock()
        count += 1
        let newCount = count
        let currentWaiter = waiter
        lock.unlock()

        guard
            let currentWaiter,
            newCount >= currentWaiter.target,
            currentWaiter.resumeGuard.tryResume()
        else { return }
        currentWaiter.continuation.resume()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    /// Waits up to `timeout` seconds for `value` to reach `target`. Returns whether it did.
    func waitForCount(_ target: Int, timeout: TimeInterval) async -> Bool {
        if meetsTarget(target) { return true }

        let resumeGuard = ResumeGuard()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            waiter = Waiter(target: target, resumeGuard: resumeGuard, continuation: continuation)
            lock.unlock()

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard resumeGuard.tryResume() else { return }
                continuation.resume()
            }
        }

        return meetsTarget(target)
    }

    private func meetsTarget(_ target: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return count >= target
    }
}

/// Lock-protected "resume this continuation exactly once" latch (duplicated from
/// `ListenerLoopbackTests`, which declares its own file-scoped copy).
private final class ResumeGuard: @unchecked Sendable {
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
