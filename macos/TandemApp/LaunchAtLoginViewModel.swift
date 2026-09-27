import Observation

/// Drives the (not-yet-built, E22-05) Settings General tab's "Launch at login" toggle over
/// ``LoginItemService`` (backlog E22-03). Presentation-independent -- no `SwiftUI` import -- unit
/// tested against a scriptable fake ``LoginItemService`` and ``LaunchAtLoginPreferenceStore``,
/// matching ``MenuBarViewModel``'s own `@Observable`/DI conventions.
///
/// `SMAppService` has no change notification, so ``refreshStatus()`` must be called whenever the
/// Settings window appears or the app becomes active (UC-01) -- this view model never polls on
/// its own.
///
/// First-successful-pairing hookup: this issue only builds ``handleSuccessfulPairing()`` as the
/// seam a completed pairing calls. `PairConfirmationViewModel.onResolved` (E14-08) fires on every
/// resolution (accept, reject, dismiss, or the connection closing), not only a successful pair,
/// so the intended wiring is:
/// `onResolved: { if !pairConfirmationViewModel.didFailToPair { launchAtLoginViewModel.handleSuccessfulPairing() } }`.
/// No such call site exists yet -- pairing isn't composed into `AppComposition` at all yet (its
/// `NoPairingWindow` stub predates E14-08's dialog ever being wired into the running app) -- so
/// this is left for whichever issue first composes the real pairing flow into `AppComposition`.
@MainActor
@Observable
final class LaunchAtLoginViewModel {
    /// The exact hint shown under the toggle when ``status`` is
    /// ``LoginItemStatus/requiresApproval`` (backlog E22-03 UI string).
    static let approvalHint = "Approve Tandem in System Settings > General > Login Items."

    private(set) var status: LoginItemStatus

    private let service: any LoginItemService
    private let preferenceStore: any LaunchAtLoginPreferenceStore

    init(service: any LoginItemService, preferenceStore: any LaunchAtLoginPreferenceStore) {
        self.service = service
        self.preferenceStore = preferenceStore
        self.status = service.status()
    }

    /// `true` while ``status`` is ``LoginItemStatus/enabled`` -- what the Settings toggle binds to.
    var isEnabled: Bool {
        status == .enabled
    }

    /// ``approvalHint`` while ``status`` is ``LoginItemStatus/requiresApproval``, else `nil`.
    var approvalHintText: String? {
        status == .requiresApproval ? Self.approvalHint : nil
    }

    /// The user flipped the Settings toggle: registers or unregisters exactly once, and marks the
    /// toggle as user-set so ``handleSuccessfulPairing()`` never overrides this choice again.
    func setEnabled(_ enabled: Bool) {
        preferenceStore.hasUserSetToggle = true
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            // `status` is re-read below regardless -- it, not this call's success, is the source
            // of truth the toggle reflects.
        }
        refreshStatus()
    }

    /// A pairing has just completed successfully (see the type doc for the intended, not-yet-wired
    /// call site). Registers the login item exactly once, only if the user has never explicitly
    /// set the toggle (backlog E22-03: "default ON after first successful pairing") -- a no-op on
    /// every later pairing once that has happened, so it never overrides an owner's own choice.
    func handleSuccessfulPairing() {
        guard !preferenceStore.hasUserSetToggle else { return }
        preferenceStore.hasUserSetToggle = true
        try? service.register()
        refreshStatus()
    }

    /// Re-reads ``status`` from ``LoginItemService`` -- call whenever the Settings window appears
    /// or the app becomes active (UC-01), since `SMAppService` has no change notification.
    func refreshStatus() {
        status = service.status()
    }
}
