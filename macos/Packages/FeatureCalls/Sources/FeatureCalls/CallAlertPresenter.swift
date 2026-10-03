/// What the user chose on a presented incoming-call alert.
public struct CallAlertResponse: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        case answer
        case decline
    }

    public let callId: String
    public let action: Action

    public init(callId: String, action: Action) {
        self.callId = callId
        self.action = action
    }
}

/// Seam between ``CallAlertViewModel`` and the system notification center (E52-06). The app's
/// adapter over `NotificationPresenter` (E30-07) is the only conforming type that touches
/// `UNUserNotificationCenter`; the seam lives here because Feature packages may not depend on each
/// other, so `FeatureCalls` cannot import `FeatureNotifications`.
public protocol CallAlertPresenter: Sendable {
    /// Presents the alert for `callId`; a second call for the same `callId` replaces it.
    func present(callId: String, title: String, body: String) async

    /// Removes the alert for `callId`, if delivered.
    func remove(callId: String) async

    /// Every Answer/Decline tap on a presented alert, in arrival order.
    var responses: AsyncStream<CallAlertResponse> { get }
}
