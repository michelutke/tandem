import FeatureCalls
import FeatureNotifications
import Foundation
@preconcurrency import UserNotifications

/// Presents incoming-call alerts (E52-06) through the shared ``NotificationPresenter`` seam
/// (E30-07) with Decline / Answer actions, and republishes their taps as ``CallAlertResponse``.
/// ``handle(_:)`` is fed from the single presenter-responses reader.
/// Lives in the app target because `FeatureCalls` may not depend on `FeatureNotifications`.
final class NotificationCallAlertPresenter: CallAlertPresenter, @unchecked Sendable {
    static let requestIdentifierPrefix = "tandem.call."

    private static let actions = [
        NotificationActionSpec(title: "Decline", isRemoteInput: false),
        NotificationActionSpec(title: "Answer", isRemoteInput: false)
    ]
    private static let declineIndex = 0
    private static let answerIndex = 1

    let responses: AsyncStream<CallAlertResponse>

    private let continuation: AsyncStream<CallAlertResponse>.Continuation
    private let presenter: any NotificationPresenter
    private let categories: CategoryRegistry

    init(presenter: any NotificationPresenter, categories: CategoryRegistry) {
        self.presenter = presenter
        self.categories = categories
        (responses, continuation) = AsyncStream<CallAlertResponse>.makeStream(bufferingPolicy: .unbounded)
    }

    func handle(_ event: NotificationResponseEvent) {
        guard let response = Self.response(from: event) else { return }
        continuation.yield(response)
    }

    func finish() {
        continuation.finish()
    }

    func present(callId: String, title: String, body: String) async {
        let categoryIdentifier = await categories.categoryIdentifier(for: Self.actions)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = categoryIdentifier
        await presenter.add(
            UNNotificationRequest(identifier: Self.requestIdentifierPrefix + callId, content: content, trigger: nil)
        )
    }

    func remove(callId: String) async {
        await presenter.removeDelivered(identifiers: [Self.requestIdentifierPrefix + callId])
    }

    static func response(from event: NotificationResponseEvent) -> CallAlertResponse? {
        guard event.requestIdentifier.hasPrefix(requestIdentifierPrefix),
              let marker = event.actionIdentifier.range(of: ".action-", options: .backwards),
              let index = Int(event.actionIdentifier[marker.upperBound...]) else { return nil }
        let callId = String(event.requestIdentifier.dropFirst(requestIdentifierPrefix.count))
        switch index {
        case answerIndex: return CallAlertResponse(callId: callId, action: .answer)
        case declineIndex: return CallAlertResponse(callId: callId, action: .decline)
        default: return nil
        }
    }
}
