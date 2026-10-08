import Foundation
@preconcurrency import UserNotifications

/// Seam between notification presentation logic and `UNUserNotificationCenter` (E30-07).
/// ``UNNotificationPresenter`` is the only conforming type that touches
/// `UNUserNotificationCenter` directly; `RecordingNotificationPresenter` (test fixture, in this
/// package's own test target) is the other, letting tests avoid the real notification-
/// authorization prompt (E00-23's manual gate covers seeing a real banner).
///
/// Category/action registration beyond ``setCategories(_:)``'s bare plumbing -- building the
/// actual `UNNotificationCategory`/`UNNotificationAction` set -- is E30-17, not this issue.
public protocol NotificationPresenter: Sendable {
    /// Presents `request`. A second call with the same `request.identifier` replaces the
    /// previously delivered notification for that identifier rather than stacking a new one
    /// (`UNUserNotificationCenter.add(_:)`'s own contract).
    /// Returns whether the system accepted it, so a wrapper can fall back to an in-app banner.
    @discardableResult
    func add(_ request: UNNotificationRequest) async -> Bool

    /// Removes already-delivered notifications matching `identifiers`.
    func removeDelivered(identifiers: [String]) async

    /// Registers the notification categories (and their actions) available for presented
    /// notifications.
    func setCategories(_ categories: Set<UNNotificationCategory>) async

    /// Every action tap or reply submission on a presented notification, in arrival order.
    var responses: AsyncStream<NotificationResponseEvent> { get }
}

/// Stand-in for `UNNotificationResponse`, which has no public initializer and so cannot appear
/// directly on ``NotificationPresenter``'s surface. ``UNNotificationPresenter`` produces one of
/// these from each real `UNNotificationResponse` it receives as a
/// `UNUserNotificationCenterDelegate`.
public struct NotificationResponseEvent: Sendable, Equatable {
    /// The identifier of the `UNNotificationRequest` this response is for.
    public let requestIdentifier: String
    /// The action the user took: `UNNotificationDefaultActionIdentifier` for a plain tap, an
    /// app-defined action identifier otherwise.
    public let actionIdentifier: String
    /// The user's typed reply, present only for a `UNTextInputNotificationResponse`.
    public let userText: String?

    public init(requestIdentifier: String, actionIdentifier: String, userText: String?) {
        self.requestIdentifier = requestIdentifier
        self.actionIdentifier = actionIdentifier
        self.userText = userText
    }
}
