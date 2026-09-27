import Foundation
import TandemCrypto
import TandemProtocol
import TandemStore
import TandemTransport

/// Which of the confirmation dialog's two actions an owner input maps to (`docs/design/ui-spec.md`
/// §9 "Default to safety"). Presentation-independent: a SwiftUI view binds a button tap, the
/// default-button role and the Escape key to these, without this type ever importing SwiftUI.
public enum PairConfirmationAction: Sendable, Equatable {
    case pair
    case dontPair
}

/// The Mac's mutual-confirmation dialog (E14-08, `docs/protocol/SPEC.md` § Pairing, "Mutual
/// confirmation"): shown once a candidate's `PairRequest` proof has verified (``PairingWindow``
/// is `.confirmationPending`), asking the owner to compare the confirmation code shown here
/// against the one the phone shows.
///
/// Presentation-independent -- no `SwiftUI`/`AppKit` import -- so it's unit-testable against a
/// real ``PairingWindow`` and a fake ``PairingCandidateSink``/`TrustStore` (over
/// `InMemoryKeychainStore`), the same way ``PairingCandidateFlow`` is. ``PairConfirmationView`` is
/// its (untested) SwiftUI presentation.
///
/// Every action is idempotent past the first: once resolved (Pair, Don't Pair, an owner-initiated
/// dismiss, or the candidate connection itself closing first), every later call is a no-op --
/// `docs/planning/decisions.md` D-70/D-73, cycle 8 (adversarial verifier M2/M3/N4): a connection
/// that already burned its one attempt via ``PairingWindow/releaseCandidate()`` before this dialog
/// resolved MUST NOT be accepted, rejected or decremented a second time by a stale click.
public final class PairConfirmationViewModel: @unchecked Sendable {
    /// Both the dialog's default (Return-key) button and the Escape key map to ``dontPair()``,
    /// never `pair` -- an explicit click is the only way to accept (ui-spec §9).
    public static let defaultAction: PairConfirmationAction = .dontPair
    public static let escapeAction: PairConfirmationAction = .dontPair

    /// "Pair {sanitized displayName}?" -- e.g. "Pair Pixel 8?".
    public let title: String
    /// "{sanitized model} · Make sure your phone shows {code grouped as XXX XXX}".
    public let bodyText: String

    private let window: PairingWindow
    private let token: PairingCandidateToken
    private let sink: any PairingCandidateSink
    private let trustStore: TrustStore
    private let handshakeSpkiDer: Data
    private let sanitizedDisplayName: String
    private let capabilities: [String]
    private let dateProvider: DateProvider
    private let onResolved: (@Sendable () -> Void)?
    private let onPaired: (@Sendable () async -> Void)?

    private let lock = NSLock()
    private var hasResolved = false

    /// - Parameters:
    ///   - displayNameBytes: The phone's raw `DeviceInfo.display_name` UTF-8 bytes, untrusted and
    ///     sanitized here (`docs/protocol/SPEC.md` "Untrusted peer strings").
    ///   - modelBytes: The phone's raw `DeviceInfo.model` UTF-8 bytes, sanitized the same way.
    ///   - confirmationCode: The 6-digit code, already computed by the caller from
    ///     `TandemCrypto.ConfirmationCode` over this candidate's stored `PairChallenge` (D-67) --
    ///     this type only formats it for display, it never derives it.
    ///   - handshakeSpkiDer: The phone SPKI DER actually observed on this candidate connection's
    ///     TLS handshake (never trusted from any field of `PairRequest`) -- committed to
    ///     `trustStore` only on ``pair()``.
    ///   - window: This candidate's ``PairingWindow``, already `.confirmationPending`.
    ///   - token: This candidate's ``PairingCandidateToken`` (E14-16 finding #2) -- every window
    ///     call below is scoped to it, so a stale dialog can never mutate a different candidate's
    ///     state.
    ///   - sink: This candidate connection's ``PairingCandidateSink``.
    ///   - trustStore: Committed to on ``pair()`` only.
    ///   - dateProvider: Injected clock for the committed `PeerRecord`'s `pairedAt`/`lastSeen`
    ///     (E00-24 seam rule -- the current time is never read directly here).
    ///   - capabilities: Forwarded as-is to the committed `PeerRecord`; this dialog has no
    ///     capability-negotiation concern of its own.
    ///   - onResolved: Called exactly once, the first time this dialog resolves by any path --
    ///     lets the (not yet built) window/coordinator that presents this dialog close it.
    ///   - onPaired: Called once, only on a successful ``pair()`` (E14-16 finding #6) -- after
    ///     trust is committed, before `PairAccepted` is sent -- so the caller can register this
    ///     connection's now-trusted session (e.g. `ControlSessionRegistry`) promptly.
    public init(
        displayNameBytes: Data,
        modelBytes: Data,
        confirmationCode: String,
        handshakeSpkiDer: Data,
        window: PairingWindow,
        token: PairingCandidateToken,
        sink: any PairingCandidateSink,
        trustStore: TrustStore,
        dateProvider: @escaping DateProvider,
        capabilities: [String] = [],
        onResolved: (@Sendable () -> Void)? = nil,
        onPaired: (@Sendable () async -> Void)? = nil
    ) {
        let sanitizedDisplayName = DisplayStringSanitizer.sanitize(displayNameBytes, kind: .name)
        let sanitizedModel = DisplayStringSanitizer.sanitize(modelBytes, kind: .name)
        self.title = "Pair \(sanitizedDisplayName)?"
        self.bodyText = "\(sanitizedModel) · Make sure your phone shows \(Self.grouped(confirmationCode))"
        self.sanitizedDisplayName = sanitizedDisplayName
        self.window = window
        self.token = token
        self.sink = sink
        self.trustStore = trustStore
        self.handshakeSpkiDer = handshakeSpkiDer
        self.capabilities = capabilities
        self.dateProvider = dateProvider
        self.onResolved = onResolved
        self.onPaired = onPaired
    }

    /// `true` once this dialog has resolved by any path (accept, deny, dismiss, or the connection
    /// closing on its own first).
    public var isResolved: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasResolved
    }

    /// The owner clicked Pair: tells the window (``PairingWindow/ownerAccepted(_:)``) and, only if
    /// that actually committed the `paired` transition, commits the handshake SPKI to the trust
    /// store and sends `PairAccepted` -- never followed by a close, the connection stays open as an
    /// ordinary session. A no-op past ``claimResolution()`` if this dialog already resolved (e.g.
    /// the connection dropped first); commits and sends nothing at all if the window no longer has
    /// this exact candidate `.confirmationPending` -- e.g. a concurrent connection-drop already
    /// released this candidate's slot before this click was processed (E14-16 finding #3,
    /// `docs/planning/decisions.md` D-73: "clicking Pair afterward... commits nothing").
    public func pair() async {
        guard claimResolution() else { return }
        guard window.ownerAccepted(token) else {
            onResolved?()
            return
        }
        commitTrust()
        await onPaired?()
        try? await sink.sendPairAccepted()
        onResolved?()
    }

    /// The owner clicked Don't Pair (also the default button and the Escape key): sends
    /// `PairRejected(REJECTED_BY_OWNER)`, closes the connection and closes the *entire* pairing
    /// window (`docs/planning/decisions.md` D-73) -- not merely one burned attempt.
    public func dontPair() async {
        await reject()
    }

    /// An owner-initiated dismiss of the dialog itself (e.g. closing its window) while the
    /// connection is still open: identical effect to ``dontPair()`` (D-73) -- a deliberate owner
    /// decision, not a retriable failure.
    public func ownerDidDismiss() async {
        await reject()
    }

    /// The candidate connection closed on its own (peer disconnect, transport error, or the
    /// window's own budget/expiry) while this dialog was still showing. That path already ran
    /// ``PairingWindow/releaseCandidate()``'s one-attempt burn before this dialog could act
    /// (D-70), so this only marks the dialog resolved -- it sends nothing, commits nothing, and
    /// never touches `window` again.
    public func connectionDidClose() {
        guard claimResolution() else { return }
        onResolved?()
    }

    private func reject() async {
        guard claimResolution() else { return }
        window.ownerDeclined(token)
        try? await sink.sendPairRejected(.rejectedByOwner)
        await sink.closePairingFailed()
        onResolved?()
    }

    private func commitTrust() {
        guard let fingerprint = try? SpkiFingerprint.of(spkiDer: handshakeSpkiDer) else { return }
        let now = dateProvider()
        let record = PeerRecord(
            fingerprint: fingerprint,
            displayName: sanitizedDisplayName,
            pairedAt: now,
            lastSeen: now,
            capabilities: capabilities
        )
        try? trustStore.put(record)
    }

    /// Atomic test-and-set on `hasResolved`: `true` only for the caller that just claimed this
    /// dialog's one-time resolution, `false` for every subsequent call (mirrors
    /// `PairingCandidateFlow.claimFailure()`).
    private func claimResolution() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasResolved { return false }
        hasResolved = true
        return true
    }

    /// Formats a 6-digit code as two groups of three (ui-spec §9: "never truncate"); returns
    /// `code` unchanged if it isn't exactly 6 characters.
    private static func grouped(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 3)
        return "\(code[..<mid]) \(code[mid...])"
    }
}
