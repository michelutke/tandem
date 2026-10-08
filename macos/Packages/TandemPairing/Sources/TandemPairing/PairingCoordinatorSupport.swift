import Foundation
import TandemCrypto
import TandemTransport

/// Holds the current pairing candidate's observed phone SPKI DER, read lazily by
/// ``PairProofVerifier`` (`nil` whenever no candidate is in flight) -- set/cleared by
/// ``PairingCoordinator/drive(session:handshakeSpkiDer:token:)`` around that one candidate's own
/// lifetime. Scoped by ``PairingCandidateToken`` (E14-16 finding #2): a stale candidate's own
/// (possibly delayed) `clear(_:)` call can only ever erase *its own* entry, never a fresher
/// candidate's DER that has since been `set(_:_:)` here -- without this, a slow teardown racing a
/// newly-admitted candidate could wipe the new candidate's DER out from under it, failing its
/// otherwise-valid proof with `BAD_PROOF`.
final class CandidateSpkiHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var current: (token: PairingCandidateToken, spkiDer: Data)?

    func set(_ token: PairingCandidateToken, _ spkiDer: Data) {
        lock.lock()
        current = (token, spkiDer)
        lock.unlock()
    }

    func get() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return current?.spkiDer
    }

    func clear(_ token: PairingCandidateToken) {
        lock.lock()
        if current?.token == token { current = nil }
        lock.unlock()
    }
}

/// Write-once, lock-protected box for the ``TandemCrypto/SpkiFingerprint`` a candidate's own
/// ``PairConfirmationViewModel/pair()`` registers into ``TandemTransport/ControlSessionRegistering``
/// (E14-16 finding #6) -- read back by ``PairingCoordinator/drive(session:handshakeSpkiDer:token:)``'s
/// own `defer` to de-register the same session once this candidate connection ends. `onPaired`
/// (whichever task the owner's `pair()` click runs on) and that `defer` (this candidate's own
/// `drive()` task) can genuinely race, hence the lock -- unlike ``CandidateSpkiHolder``, this box
/// is never reused across candidates (a fresh one is made per ``drive(session:handshakeSpkiDer:token:)``
/// call), so it needs no token scoping of its own.
final class FingerprintBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SpkiFingerprint?

    var value: SpkiFingerprint? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ fingerprint: SpkiFingerprint) {
        lock.lock()
        stored = fingerprint
        lock.unlock()
    }
}

/// Atomic test-and-set flag a candidate's ``PairConfirmationViewModel`` resolution flips exactly
/// once, from whatever task the owner (or a DEBUG auto-confirm hook) resolves it on -- read by
/// ``PairingCoordinator/drive(session:handshakeSpkiDer:token:)``'s own frame loop, on its own task,
/// so that loop stops driving ``PairingCandidateFlow`` once this candidate's outcome is no longer its
/// concern (mirrors ``PairingCandidateFlow/claimFailure()``'s own idiom).
final class ResolutionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var resolved = false

    var isResolved: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resolved
    }

    func resolve() {
        lock.lock()
        resolved = true
        lock.unlock()
    }
}
