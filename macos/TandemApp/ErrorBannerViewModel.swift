import Foundation
import Observation
import TandemProtocol

/// A persistent, secret-free banner for a fail-closed connection (E22-07, invariant 5): each of
/// pin mismatch, unknown peer, and version mismatch shows its own exact text naming the peer where
/// known (backlog E22-07 "UI strings (exact)"). Once shown, the banner is dismissed only by
/// ``dismiss()`` -- there is no timer or other automatic dismissal, proved by
/// `errorBannerViewModel_after1hWithoutAck_bannerStillShown` advancing a `ManualTestClock` (E00-24)
/// by an hour of virtual time with no effect.
///
/// Structurally secret-free by construction: this type only ever observes
/// ``ConnectionStateMachine/ConnectionState/failed(_:)``'s ``CloseCode`` (a plain, payload-free
/// enum case) and the constructor's own `peerName` `String?` -- neither carries certificate DER,
/// key material, or any other pairing-secret bytes, so no code path here could render them even by
/// mistake.
///
/// Presentation-independent -- no `SwiftUI` import -- unit-tested against the E12-12
/// `FakeTandemSession`'s own ``TandemSession/state`` stream (`@testable import TandemProtocol`),
/// the same seam ``MenuBarViewModel`` already uses for connection state. ``ErrorBannerView`` is
/// its SwiftUI presentation.
@MainActor
@Observable
final class ErrorBannerViewModel {
    /// The exact banner text to show, or `nil` while nothing is shown (before the first
    /// fail-closed event, or after ``dismiss()``).
    private(set) var message: String?

    /// Threaded through now (E00-24 seam rule), exactly like ``MenuBarViewModel``'s own `clock`:
    /// this view model starts no timer of its own, so it is never read, but its presence is what
    /// lets `errorBannerViewModel_after1hWithoutAck_bannerStillShown` prove that advancing a
    /// `ManualTestClock` by an hour has no effect on ``message``.
    private let clock: any Clock<Duration>

    private let peerName: String?

    @ObservationIgnored
    private nonisolated(unsafe) var observationTask: Task<Void, Never>?

    /// - Parameters:
    ///   - stateStream: The connection's own state stream (``TandemSession/state``), or `nil` if
    ///     there is nothing to observe yet.
    ///   - peerName: The peer's display name, if already known (e.g. a previously-paired device
    ///     whose key changed) -- `nil` for a peer this Mac has never recognized, which is exactly
    ///     the ``CloseCode/pinMismatch`` "unknown peer" wording (backlog E22-07): the same close
    ///     code covers both cases (SPEC.md #errors-and-close-codes row 2), distinguished only by
    ///     whether a name is already on hand.
    init(
        stateStream: AsyncStream<ConnectionStateMachine.ConnectionState>?,
        peerName: String?,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.peerName = peerName
        self.clock = clock
        if let stateStream {
            observe(stateStream)
        }
    }

    deinit {
        observationTask?.cancel()
    }

    /// The "OK" button's action (backlog E22-07 "Dismiss button (exact): OK"): the only way
    /// ``message`` is ever cleared.
    func dismiss() {
        message = nil
    }

    private func observe(_ stream: AsyncStream<ConnectionStateMachine.ConnectionState>) {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            for await connectionState in stream {
                guard !Task.isCancelled else { return }
                self?.apply(connectionState)
            }
        }
    }

    private func apply(_ connectionState: ConnectionStateMachine.ConnectionState) {
        guard case .failed(let closeCode) = connectionState,
              let text = Self.message(for: closeCode, peerName: peerName) else { return }
        message = text
    }

    /// The pure reducer from a fail-closed ``CloseCode`` to this banner's exact text (backlog
    /// E22-07 "UI strings (exact)"), or `nil` for a ``CloseCode`` this banner has no text for (e.g.
    /// ``CloseCode/malformedFrame``, ``CloseCode/creditViolation``, ``CloseCode/protocolTimeout``,
    /// ``CloseCode/limitExceeded`` -- already surfaced by ``ErrorPresenter``'s status-line text,
    /// E12-10).
    static func message(for closeCode: CloseCode, peerName: String?) -> String? {
        switch closeCode {
        case .pinMismatch:
            if let peerName {
                return "\(peerName) presented an unexpected key. Connection refused."
            } else {
                return "An unpaired device tried to connect and was refused."
            }
        case .versionMismatch:
            let name = peerName ?? "This device"
            return "\(name) runs an incompatible Tandem version. Update both apps."
        case .malformedFrame, .creditViolation, .protocolTimeout, .limitExceeded, .ticketRejected:
            return nil
        }
    }
}
