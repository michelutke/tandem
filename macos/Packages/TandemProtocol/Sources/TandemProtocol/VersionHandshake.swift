import Foundation

/// Version/capability handshake over the CONTROL channel (E01-06, docs/protocol/SPEC.md
/// #versioning-and-capability-negotiation; `docs/planning/decisions.md` D-63). Swift counterpart
/// to the Android `VersionHandshake` (E12-15).
///
/// Each side sends its own `VersionHello` as the first frame it transmits on `.control` (assigned
/// `seq = 1` by ``ChannelMultiplexer``'s own outgoing counter) without waiting for the peer's,
/// then races the peer's `VersionHello` against ``helloDeadline`` (docs/protocol/SPEC.md
/// #timeouts-connection-limits-and-resource-caps, E01-22) measured on the injected `Clock` --
/// never an unseamed wall-clock read or an implicit sleep call (this package's seam rule, E00-24).
///
/// ``send(_:payload:)`` is how every other channel's payload MUST reach the wire: it suspends
/// while ``session`` is still ``NegotiatedSession/pending``, so no application frame is ever
/// written before both hellos have been exchanged (SPEC.md "Exchange rule"), and throws once
/// ``session`` has resolved to ``NegotiatedSession/failed(_:)``.
public actor VersionHandshake {
    /// This protocol revision's own `VersionHello` fields (docs/protocol/SPEC.md
    /// #versioning-and-capability-negotiation): `major = 1`, `minor = 0`; `capabilities` is left
    /// at its wire default of 0 (no bit assigned yet).
    static let ownMajor: UInt32 = 1
    static let ownMinor: UInt32 = 0

    /// `VersionHello` deadline: 5 s after TLS completion, both sides (SPEC.md §10, E01-22).
    static let helloDeadline: Duration = .seconds(5)

    /// Outcome of the handshake, exposed so other callers can gate their own sends on it. Swift
    /// counterpart to the Android `NegotiatedSession` (E12-15).
    public enum NegotiatedSession: Sendable, Equatable {
        /// Neither this side's own hello has resolved against the peer's yet -- no non-`.control`
        /// send may reach the wire while this holds.
        case pending
        /// Both hellos exchanged with matching `major`. `peerCapabilities` is the peer's raw
        /// `VersionHello.capabilities` value, exposed but never acted on (SPEC.md "Capability
        /// mismatch": no bit is assigned meaning in this protocol version, and an unrecognized
        /// bit MUST be ignored, never treated as an error).
        case ready(peerCapabilities: UInt64)
        /// The handshake failed; the connection MUST be treated as unusable from here on
        /// (invariant 5, fail closed).
        case failed(HandshakeFailure)
    }

    /// Why a handshake failed (docs/protocol/SPEC.md #errors-and-close-codes).
    public enum HandshakeFailure: Sendable, Equatable {
        /// The peer's `major` differs from ``ownMajor`` -- always fatal regardless of `minor`
        /// (SPEC.md "Version mismatch"). Wire close code `VERSION_MISMATCH`.
        case versionMismatch
        /// No peer `VersionHello` arrived within ``helloDeadline`` of this handshake starting.
        /// Wire close code `PROTOCOL_TIMEOUT` (E01-22).
        case protocolTimeout
    }

    /// Thrown by ``send(_:payload:)`` once ``session`` has resolved to
    /// ``NegotiatedSession/failed(_:)``, whether it already had when called or resolved to that
    /// while the call was suspended.
    public enum HandshakeError: Error, Sendable, Equatable {
        case failed(HandshakeFailure)
    }

    private let multiplexer: ChannelMultiplexer
    private let clock: any Clock<Duration>

    public private(set) var session: NegotiatedSession = .pending
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []

    public init(multiplexer: ChannelMultiplexer, clock: any Clock<Duration>) {
        self.multiplexer = multiplexer
        self.clock = clock
    }

    /// Runs the handshake once: sends this side's own `VersionHello`, then resolves ``session``
    /// either from the peer's `VersionHello` (``NegotiatedSession/ready(peerCapabilities:)`` on a
    /// matching `major`, ``HandshakeFailure/versionMismatch`` otherwise) or, absent one before
    /// ``helloDeadline`` elapses, ``HandshakeFailure/protocolTimeout``. Every
    /// ``send(_:payload:)`` call suspended on ``session`` still being ``NegotiatedSession/pending``
    /// resumes once this returns. Callers should invoke this exactly once per connection, after
    /// the multiplexer has started reading (``ChannelMultiplexer/start()``).
    public func run() async {
        var ownHello = Tandem_V1_VersionHello()
        ownHello.major = Self.ownMajor
        ownHello.minor = Self.ownMinor
        try? await multiplexer.send(.control, payload: .versionHello(ownHello))

        let controlFrames = await multiplexer.inbound(.control)
        let clock = clock

        let outcome = await withTaskGroup(of: RaceOutcome.self) { group in
            group.addTask {
                var iterator = controlFrames.makeAsyncIterator()
                while let frame = await iterator.next() {
                    if case .versionHello(let peerHello)? = frame.payload {
                        return .peerHello(peerHello)
                    }
                }
                return .deadlineElapsed
            }
            group.addTask {
                try? await clock.sleep(for: Self.helloDeadline)
                return .deadlineElapsed
            }
            let first = await group.next() ?? .deadlineElapsed
            group.cancelAll()
            return first
        }

        switch outcome {
        case .peerHello(let peerHello) where peerHello.major == Self.ownMajor:
            resolve(.ready(peerCapabilities: peerHello.capabilities))
        case .peerHello:
            resolve(.failed(.versionMismatch))
        case .deadlineElapsed:
            resolve(.failed(.protocolTimeout))
        }
    }

    /// Sends `payload` on `channel` once ``session`` has resolved to
    /// ``NegotiatedSession/ready(peerCapabilities:)``, suspending until then -- so no application
    /// frame reaches the wire before both hellos have been exchanged (SPEC.md "Exchange rule").
    ///
    /// - Throws: ``HandshakeError/failed(_:)`` if ``session`` already is, or becomes,
    ///   ``NegotiatedSession/failed(_:)``; whatever ``ChannelMultiplexer/send(_:payload:)`` throws
    ///   otherwise.
    func send(_ channel: Tandem_V1_Channel, payload: Tandem_V1_Envelope.OneOf_Payload) async throws {
        try await awaitReady()
        try await multiplexer.send(channel, payload: payload)
    }

    private func awaitReady() async throws {
        switch session {
        case .ready:
            return
        case .failed(let failure):
            throw HandshakeError.failed(failure)
        case .pending:
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                readyWaiters.append(continuation)
            }
        }
    }

    private func resolve(_ outcome: NegotiatedSession) {
        guard case .pending = session else { return }
        session = outcome
        let waiters = readyWaiters
        readyWaiters = []
        for waiter in waiters {
            switch outcome {
            case .ready:
                waiter.resume()
            case .failed(let failure):
                waiter.resume(throwing: HandshakeError.failed(failure))
            case .pending:
                preconditionFailure("resolve(_:) must never be called with .pending")
            }
        }
    }

    /// One race leg's result (``run()``): either the peer's `VersionHello`, or ``helloDeadline``
    /// elapsing first. Not itself part of ``NegotiatedSession`` -- `run()` still has to compare
    /// `major` before it knows whether a `.peerHello` leg is actually a success.
    private enum RaceOutcome: Sendable {
        case peerHello(Tandem_V1_VersionHello)
        case deadlineElapsed
    }
}
