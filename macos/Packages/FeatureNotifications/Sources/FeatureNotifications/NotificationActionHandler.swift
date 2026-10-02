import Foundation
import TandemProtocol
@preconcurrency import UserNotifications

/// Forwards a Mac-side action tap or text-input reply to the phone as `NotificationAction` on the
/// NOTIFY channel, and reacts to the phone's `NotificationActionResult` (E30-08).
///
/// The action index is parsed from the `UNNotificationAction` identifier ``CategoryRegistry``
/// assigns (`"<category>.action-<index>"`); a response with any other action identifier (the
/// default tap, a dismissal) is not an action and is ignored here.
public actor NotificationActionHandler {
    /// UC-09 alternate: body of the replacement notification shown when the phone no longer has
    /// the notification an action was aimed at.
    public static let noLongerAvailableBody = "Notification no longer available on phone"

    private static let actionMarker = ".action-"

    private let presenter: any NotificationPresenter
    private let session: any TandemSession

    public init(presenter: any NotificationPresenter, session: any TandemSession) {
        self.presenter = presenter
        self.session = session
    }

    /// Sends `NotificationAction{key, actionIndex, replyText}` for `event`; `replyText` is
    /// `event.userText` unchanged, or empty for a plain action tap.
    public func handle(_ event: NotificationResponseEvent) async {
        guard let actionIndex = Self.actionIndex(from: event.actionIdentifier) else { return }
        var action = Tandem_V1_NotificationAction()
        action.key = event.requestIdentifier
        action.actionIndex = actionIndex
        action.replyText = event.userText ?? ""
        try? await session.send(.notify, payload: .notificationAction(action))
    }

    /// On `GONE`, removes the stale delivered notification for `result.key` and presents a
    /// replacement under the same identifier saying it is no longer available. Other statuses
    /// need no Mac-side change.
    public func handle(_ result: Tandem_V1_NotificationActionResult) async {
        guard result.status == .gone else { return }
        await presenter.removeDelivered(identifiers: [result.key])
        let content = UNMutableNotificationContent()
        content.body = Self.noLongerAvailableBody
        await presenter.add(UNNotificationRequest(identifier: result.key, content: content, trigger: nil))
    }

    private static func actionIndex(from actionIdentifier: String) -> Int32? {
        guard let range = actionIdentifier.range(of: actionMarker, options: .backwards) else { return nil }
        return Int32(actionIdentifier[range.upperBound...])
    }
}

/// Feeds every ``NotificationPresenter/responses`` event to `handler` until the stream finishes.
public func startNotificationActionResponseReader(
    presenter: any NotificationPresenter,
    handler: NotificationActionHandler
) -> Task<Void, Never> {
    Task {
        for await event in presenter.responses {
            await handler.handle(event)
        }
    }
}
