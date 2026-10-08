import Foundation
@preconcurrency import UserNotifications

/// The only type in this module that touches `UNUserNotificationCenter` directly (E30-07).
/// Delivers requests immediately (`trigger: nil` -- there is no scheduling concept for a mirrored
/// notification), forwards delivered-notification removal straight through, and republishes
/// every `UNUserNotificationCenterDelegate` callback as a ``NotificationResponseEvent`` on
/// ``responses``.
///
/// Whether this delegate's callback fires at all, and whether the resulting banner actually
/// appears, depends on notification authorization the user grants on a physical Mac -- that is
/// the E00-23 manual gate, not something this type can verify itself.
public final class UNNotificationPresenter: NSObject, NotificationPresenter, @unchecked Sendable {
    private let center: UNUserNotificationCenter
    public let responses: AsyncStream<NotificationResponseEvent>
    private let responsesContinuation: AsyncStream<NotificationResponseEvent>.Continuation

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        let (stream, continuation) = AsyncStream<NotificationResponseEvent>.makeStream(
            bufferingPolicy: .unbounded
        )
        responses = stream
        responsesContinuation = continuation
        super.init()
        center.delegate = self
    }

    @discardableResult
    public func add(_ request: UNNotificationRequest) async -> Bool {
        do {
            try await center.add(request)
            return true
        } catch {
            NotificationsLog.event("system add failed")
            return false
        }
    }

    public func removeDelivered(identifiers: [String]) async {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    public func setCategories(_ categories: Set<UNNotificationCategory>) async {
        center.setNotificationCategories(categories)
    }
}

extension UNNotificationPresenter: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userText = (response as? UNTextInputNotificationResponse)?.userText
        responsesContinuation.yield(
            NotificationResponseEvent(
                requestIdentifier: response.notification.request.identifier,
                actionIdentifier: response.actionIdentifier,
                userText: userText
            )
        )
        completionHandler()
    }
}
