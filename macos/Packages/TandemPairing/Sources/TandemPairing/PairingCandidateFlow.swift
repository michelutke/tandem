import Foundation
import TandemTransport

/// Drives one pairing-candidate connection through `docs/protocol/SPEC.md` §2 "Frame order on a
/// pairing-candidate connection", on top of ``PairingWindow`` (E14-02) and a ``PairingCandidateSink``
/// (E14-09). Centralizes every failure path for this receive flow -- a bad proof, a wrong payload
/// (anything except `Heartbeat`), or the window closing (e.g. its 120 s expiry) while this candidate
/// is still in flight -- so each one, and only these, sends `PairRejected(PAIRING_UNAVAILABLE)` and
/// closes the connection with `PAIRING_FAILED` exactly once (`docs/planning/decisions.md` D-70: a
/// candidate connection burns **at most one** attempt in total, regardless of how many of these
/// events it triggers before closing).
///
/// The 10 s `PairRequest` deadline (local reason `TIMEOUT`) is driven from outside this type (the
/// active watcher lives in ``PairingCoordinator/drive(session:handshakeSpkiDer:token:)``, since it
/// needs the injected `Clock` to actually sleep): ``requestDeadlineElapsed()`` is what that watcher
/// calls once it fires, and -- unlike every other failure path here -- sends no `PairRejected` at
/// all (`docs/planning/decisions.md` D-72).
///
/// Like ``PairingWindow`` itself, this type settles no time on its own beyond that one active
/// watcher: the mid-flight expiry check runs only when some other event next reaches this
/// candidate (in production, the periodic `Heartbeat` §7 already requires replying to; tests call
/// ``heartbeatReceived()`` directly after advancing a `ManualTestClock`).
public final class PairingCandidateFlow: @unchecked Sendable {
    private let window: PairingWindow
    private let sink: any PairingCandidateSink
    private let token: PairingCandidateToken

    private let lock = NSLock()
    private var hasFailed = false

    /// - Parameter token: This candidate's slot claim, from the ``PairingWindow/admitCandidate()``
    ///   call that admitted it -- presented to every later ``PairingWindow`` call this type makes
    ///   for the same candidate, so a stale call from a since-superseded flow can only ever no-op
    ///   (`docs/planning/decisions.md` D-73, adversarial-verifier finding).
    public init(window: PairingWindow, sink: any PairingCandidateSink, token: PairingCandidateToken) {
        self.window = window
        self.sink = sink
        self.token = token
    }

    /// Called once both sides' `VersionHello` exchange completes on this admitted candidate.
    /// Generates and sends this candidate's `PairChallenge` as the very next `CONTROL` frame. A
    /// no-op (returns `nil`) if the window didn't have this candidate `.admitted` -- wrong call
    /// order, or the window already closed/regenerated first (``PairingWindow`` guards this, not a
    /// failure this type reports).
    @discardableResult
    public func hellosCompleted() async -> Data? {
        guard let challenge = window.candidateHellosCompleted(token) else { return nil }
        try? await sink.sendPairChallenge(challenge)
        return challenge
    }

    /// A `PairRequest { proof }` arrived. A valid proof moves the candidate to awaiting the
    /// owner's confirmation (E14-08's concern from here); an invalid one -- including one the
    /// window rejects outright because it's no longer open, or this candidate is no longer
    /// `awaitingRequest` -- fails this candidate (`docs/protocol/SPEC.md` §2, local reason
    /// `BAD_PROOF`).
    public func pairRequestReceived(proof: Data) async {
        guard window.submitPairRequest(token, proof: proof) == .rejected else { return }
        await fail()
    }

    /// Any payload other than the expected next message in the sequence, except `Heartbeat`
    /// (`docs/protocol/SPEC.md` §2 "Frame order", case 4, local reason `MALFORMED`): a second
    /// `PairChallenge`, a `PairRequest` before `PairChallenge`, a duplicate `PairRequest`, or any
    /// other payload type. A no-op if this candidate already failed via another path (D-70: at
    /// most one attempt burned per connection, in total).
    public func wrongPayloadReceived() async {
        guard !isAlreadyFailed() else { return }
        window.releaseCandidate(token)
        await fail()
    }

    /// A `Heartbeat` on this pairing-candidate connection: never itself a pairing failure, at any
    /// point (`docs/planning/decisions.md` D-69). Also the point at which this type reconciles
    /// against ``PairingWindow``'s own lazily-settled expiry: if the window has since closed while
    /// this candidate was still in flight (e.g. its 120 s expiry elapsed while a confirmation
    /// dialog was pending), this candidate connection is failed too -- it sends
    /// `PairRejected(PAIRING_UNAVAILABLE)` and closes, but burns no additional attempt (the window
    /// closing already accounts for the whole window's budget). Excludes ``PairingWindowClosedReason/paired``
    /// (E14-16 finding #4): a `Heartbeat` can land on this exact connection's own frame loop after
    /// its own ``PairConfirmationViewModel/pair()`` has already committed the window to `.paired`
    /// but while that same call is still suspended awaiting `PairAccepted`'s send -- that is this
    /// connection succeeding, not failing, so it must never be treated as a reason to reject it. Once
    /// the owner has accepted, this connection is an ordinary session from here on, and a `Heartbeat`
    /// on it MUST NOT be treated as a pairing failure (a coordinator that keeps routing `Heartbeat`
    /// through this type after `PairAccepted` would otherwise reject the very session it just
    /// accepted).
    public func heartbeatReceived() async {
        window.heartbeatReceived()
        guard let reason = window.closedReason, reason != .paired else { return }
        await fail()
    }

    /// The underlying connection closed for a reason other than this type's own
    /// ``pairRequestReceived(proof:)``/``wrongPayloadReceived()``/``heartbeatReceived()`` failures
    /// -- e.g. a peer disconnect or transport error. Frees the candidate slot and burns one
    /// attempt (``PairingWindow/releaseCandidate(_:)``), a no-op if this candidate already failed
    /// via one of those paths (D-70: at most one attempt burned per connection, in total).
    public func connectionClosed() {
        guard !isAlreadyFailed() else { return }
        window.releaseCandidate(token)
    }

    /// The active 10 s `PairRequest` deadline (E14-16 finding #5, `docs/protocol/SPEC.md` §10
    /// "`PairRequest` deadline") elapsed with no `PairRequest` yet received on this connection.
    /// Burns one attempt and closes the connection -- but, unlike ``fail()``, sends no
    /// `PairRejected` at all (`docs/planning/decisions.md` D-72: local reason `TIMEOUT` is the one
    /// `PAIRING_FAILED` reason with no wire signal). A no-op if this candidate already moved past
    /// `awaitingRequest` (a `PairRequest`, valid or not, already arrived) or already failed via
    /// another path -- D-70's "at most one attempt burned per connection" still holds.
    ///
    /// Doesn't trust ``PairingWindow/requestDeadlineElapsed(_:)``'s own return value alone (E14-24):
    /// that call reports `false` not only when some other locked call already burned *this*
    /// candidate's 10 s sub-deadline first (``PairingWindow``'s `deadlineBurnedToken` already
    /// covers that, per E14-16), but also when the window's own, entirely separate 120 s
    /// whole-window expiry is what settled first instead -- that branch returns before ever
    /// reaching the per-candidate deadline check, so `deadlineBurnedToken` is never set for
    /// `token`, and this watcher must not conclude "already handled" and leave the connection open.
    /// So this also closes whenever `token` is no longer one ``PairingWindow`` considers in flight
    /// at all, rather than only when it burned the deadline itself just now -- safe either way:
    /// any attempt burn already happened inside that one locked ``PairingWindow`` call (never
    /// here), and ``claimFailure()`` still guards this connection's own close/`PairRejected` to at
    /// most once regardless of which path got there first.
    public func requestDeadlineElapsed() async {
        let burnedByWindow = window.requestDeadlineElapsed(token)
        guard burnedByWindow || !window.candidateInFlight(token) else { return }
        guard claimFailure() else { return }
        await sink.closePairingFailed()
    }

    /// Sends `PairRejected(PAIRING_UNAVAILABLE)` and closes with `PAIRING_FAILED`, exactly once
    /// per connection.
    private func fail() async {
        guard claimFailure() else { return }
        try? await sink.sendPairRejected(.pairingUnavailable)
        await sink.closePairingFailed()
    }

    /// Atomic test-and-set on `hasFailed`: `true` only for the caller that just claimed this
    /// candidate's one-time failure, `false` for every subsequent call.
    private func claimFailure() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasFailed { return false }
        hasFailed = true
        return true
    }

    /// Peeks `hasFailed` without claiming it, so ``wrongPayloadReceived()``/``connectionClosed()``
    /// can skip touching ``window`` at all once this candidate has already failed via any path.
    private func isAlreadyFailed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasFailed
    }
}
