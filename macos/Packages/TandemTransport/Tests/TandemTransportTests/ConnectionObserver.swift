import Foundation
import Network

/// Observes a client `NWConnection`'s `stateUpdateHandler` for the loopback rejection tests
/// (E12-01). Gotcha 5 (`docs/spikes/nwlistener-mtls.md`): several rejection classes -- a TLS
/// version mismatch, an ALPN mismatch -- surface to the *client* role as `.waiting`, never a
/// terminal `.failed`. So rejection here is never "observed `.failed`"; it is "did not reach
/// `.ready` within a bounded deadline" (`waitForReady`). Other rejection classes -- no client
/// certificate, no ALPN offered -- instead reach `.ready` transiently (the client completes its
/// side of the handshake before the server evaluates and rejects it), so those callers pair
/// `waitForReady` with an active `.receive()` to observe the server's subsequent close (see
/// `ListenerLoopbackTests.waitForReceiveEOFOrError`). Every wait here is bounded -- never an
/// unbounded wait -- and uses `DispatchQueue.asyncAfter` rather than `Task.sleep` (banned by the
/// `injected_clock_only` SwiftLint rule in this package).
actor ConnectionObserver {
    private var reachedReady = false
    private var readyContinuation: CheckedContinuation<Bool, Never>?

    nonisolated func attach(to connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handle(state) }
        }
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            reachedReady = true
            if let readyContinuation {
                self.readyContinuation = nil
                readyContinuation.resume(returning: true)
            }
        default:
            break
        }
    }

    /// Waits up to `timeout` seconds for `.ready`. Returns whether it was reached before the
    /// deadline elapsed.
    func waitForReady(timeout: TimeInterval) async -> Bool {
        if reachedReady { return true }
        return await withCheckedContinuation { continuation in
            readyContinuation = continuation
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                Task { await self.timeoutReady() }
            }
        }
    }

    private func timeoutReady() {
        guard let readyContinuation else { return }
        self.readyContinuation = nil
        readyContinuation.resume(returning: false)
    }
}
