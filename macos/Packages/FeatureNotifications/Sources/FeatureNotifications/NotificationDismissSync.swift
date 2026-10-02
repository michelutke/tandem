import Foundation
import TandemProtocol
@preconcurrency import UserNotifications

/// Keeps dismissals in sync between phone and Mac (E30-18). A received android-origin
/// `NotificationDismiss` removes the delivered notification; a user dismissal on the Mac
/// (`UNNotificationDismissActionIdentifier`, enabled by `.customDismissAction` in E30-17) sends
/// `NotificationDismiss{origin: macos}`. Programmatic removal goes through
/// ``NotificationPresenter/removeDelivered(identifiers:)`` and never produces a response event,
/// so applying a phone dismissal cannot echo back.
public struct NotificationDismissSync: Sendable {
    private let presenter: any NotificationPresenter
    private let session: any TandemSession

    public init(presenter: any NotificationPresenter, session: any TandemSession) {
        self.presenter = presenter
        self.session = session
    }

    /// Removes the delivered notification for an android-origin dismiss; other origins are ignored.
    public func handle(_ dismiss: Tandem_V1_NotificationDismiss) async {
        guard dismiss.origin == .android else { return }
        await presenter.removeDelivered(identifiers: [dismiss.key])
    }

    /// Forwards a user dismissal on the Mac to the phone immediately; other actions are ignored.
    public func handle(_ response: NotificationResponseEvent) async {
        guard response.actionIdentifier == UNNotificationDismissActionIdentifier else { return }
        var dismiss = Tandem_V1_NotificationDismiss()
        dismiss.key = response.requestIdentifier
        dismiss.origin = .macos
        try? await session.send(.notify, payload: .notificationDismiss(dismiss))
    }
}
