import FeatureCalls
import FeatureNotifications
import Foundation
@preconcurrency import UserNotifications

/// Presents incoming-call alerts (E52-06) through the shared ``NotificationPresenter`` seam
/// (E30-07) with Decline / Answer actions, and republishes their taps as ``CallAlertResponse``.
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

    private let presenter: any NotificationPresenter
    private let categories: CategoryRegistry
    private let observationTask: Task<Void, Never>

    init(presenter: any NotificationPresenter, categories: CategoryRegistry) {
        self.presenter = presenter
        self.categories = categories
        let (stream, continuation) = AsyncStream<CallAlertResponse>.makeStream(bufferingPolicy: .unbounded)
        responses = stream
        observationTask = Task {
            for await event in presenter.responses {
                guard let response = Self.response(from: event) else { continue }
                continuation.yield(response)
            }
            continuation.finish()
        }
    }

    deinit {
        observationTask.cancel()
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
