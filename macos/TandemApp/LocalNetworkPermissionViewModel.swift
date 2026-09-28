import Foundation
import Observation
import TandemTransport

/// Explains a Local Network privacy denial and offers a link to System Settings (E21-03, backlog
/// "UI strings (exact)"): observes a ``BonjourPublisher``'s ``BonjourPublisher/errors`` stream
/// (TandemTransport, E21-02) and, on ``BonjourPublishError/policyDenied``, shows the exact
/// explanation text and button. Presentation-independent -- no `SwiftUI` import -- unit-tested
/// against a plain `AsyncStream<BonjourPublishError>` and a recording fake ``URLOpener``,
/// mirroring ``MenuBarViewModel``'s own `@Observable`/DI conventions.
///
/// Takes the already-opened `errors` stream (like ``MenuBarViewModel``'s `stateStream`), not the
/// whole ``BonjourPublisher`` -- this view model never publishes or unpublishes anything itself.
@MainActor
@Observable
final class LocalNetworkPermissionViewModel {
    /// Exact explanation text (backlog E21-03 "UI strings (exact)").
    static let explanationText = "Tandem needs Local Network access so your phone can find this Mac."

    /// Exact button title (backlog E21-03 "UI strings (exact)").
    static let openSettingsButtonTitle = "Open System Settings"

    /// Privacy & Security > Local Network settings deep link (backlog E21-03 acceptance: "The
    /// button opens the Privacy & Security > Local Network settings URL").
    private static let localNetworkSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"
    )!

    /// `true` once a ``BonjourPublishError/policyDenied`` error has been observed -- the banner
    /// this drives (``MenuBarContentView``'s sibling `LocalNetworkPermissionBannerView`) is hidden
    /// until then, and stays shown afterwards (the permission is never re-checked without a
    /// relaunch, matching `SMAppService`'s own no-change-notification behavior
    /// ``LaunchAtLoginViewModel`` already documents).
    private(set) var isDenied = false

    private let urlOpener: any URLOpener

    @ObservationIgnored
    private nonisolated(unsafe) var observationTask: Task<Void, Never>?

    init(errors: AsyncStream<BonjourPublishError>, urlOpener: any URLOpener) {
        self.urlOpener = urlOpener
        observe(errors)
    }

    deinit {
        observationTask?.cancel()
    }

    /// The user tapped ``openSettingsButtonTitle`` -- opens the Local Network privacy pane via
    /// the injected ``URLOpener`` seam, never `NSWorkspace` directly (so this stays testable
    /// without touching the real Settings app).
    func openSettingsTapped() {
        urlOpener.open(Self.localNetworkSettingsURL)
    }

    private func observe(_ stream: AsyncStream<BonjourPublishError>) {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            for await error in stream {
                guard !Task.isCancelled else { return }
                guard error == .policyDenied else { continue }
                self?.isDenied = true
            }
        }
    }
}
