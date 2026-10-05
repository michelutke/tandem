import Foundation
import TandemProtocol
import TandemTransport

/// The one long-lived ``PairingWindowState``/``PairingCandidateDriver`` a production listener is
/// wired against (E22-14): the listener is built once at launch, but a pairing window only exists
/// while the owner has opened one ("Add phone"), so this fronts a fresh ``PairingCoordinator`` per
/// ``open()`` and fails closed (invariant 5) -- no admission, no driving -- whenever none is open.
///
/// Every ``open()`` mints a new coordinator, hence a new secret, and cancels the previous one's
/// window, so a secret is never valid across two opens (invariant 6). A window that timed out,
/// was cancelled or already paired stays closed until the owner opens another.
public final class PairingWindowHost: PairingWindowState, PairingCandidateDriver, @unchecked Sendable {
    private let makeCoordinator: @Sendable () throws -> PairingCoordinator
    private let lock = NSLock()
    private var current: PairingCoordinator?

    public init(makeCoordinator: @escaping @Sendable () throws -> PairingCoordinator) {
        self.makeCoordinator = makeCoordinator
    }

    /// Opens a fresh single-use window, cancelling any previous one, and returns its coordinator
    /// (QR via ``PairingCoordinator/viewModel``). Throws, opening nothing, if the factory can't build one.
    @discardableResult
    public func open() throws -> PairingCoordinator {
        let coordinator = try makeCoordinator()
        lock.lock()
        let previous = current
        current = coordinator
        lock.unlock()
        previous?.window.cancel()
        return coordinator
    }

    /// Owner cancel: closes the current window, if any.
    public func cancel() {
        coordinator?.window.cancel()
    }

    /// The coordinator of the most recently opened window, open or not.
    public var coordinator: PairingCoordinator? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public var isOpen: Bool {
        coordinator?.window.isOpen ?? false
    }

    public func admitCandidate() -> PairingCandidateToken? {
        coordinator?.window.admitCandidate()
    }

    public func releaseCandidate(_ token: PairingCandidateToken) {
        coordinator?.window.releaseCandidate(token)
    }

    public func drive(session: any TandemSession, handshakeSpkiDer: Data, token: PairingCandidateToken) async {
        guard let coordinator else {
            await session.close()
            return
        }
        await coordinator.drive(session: session, handshakeSpkiDer: handshakeSpkiDer, token: token)
    }

    public func candidateAbandoned(token: PairingCandidateToken) async {
        await coordinator?.candidateAbandoned(token: token)
    }
}
