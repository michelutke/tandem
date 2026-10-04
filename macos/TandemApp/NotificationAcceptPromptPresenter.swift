import FeatureFiles
import FeatureNotifications
import Foundation
@preconcurrency import UserNotifications

/// Presents the incoming-file Accept / Decline prompt through the shared ``NotificationPresenter``
/// seam and republishes the user's taps as ``AcceptPromptResponse``. One instance per attached
/// session; ``handle(_:)`` is fed from the single presenter-responses reader, never from a second
/// subscription to `NotificationPresenter.responses`.
final class NotificationAcceptPromptPresenter: AcceptPromptPresenter, @unchecked Sendable {
    static let requestIdentifierPrefix = "tandem.accept."

    private static let actions = [
        NotificationActionSpec(title: "Decline", isRemoteInput: false),
        NotificationActionSpec(title: "Accept", isRemoteInput: false)
    ]
    private static let declineIndex = 0
    private static let acceptIndex = 1

    let responses: AsyncStream<AcceptPromptResponse>

    private let continuation: AsyncStream<AcceptPromptResponse>.Continuation
    private let presenter: any NotificationPresenter
    private let categories: CategoryRegistry

    init(presenter: any NotificationPresenter, categories: CategoryRegistry) {
        self.presenter = presenter
        self.categories = categories
        (responses, continuation) = AsyncStream<AcceptPromptResponse>.makeStream(bufferingPolicy: .unbounded)
    }

    func present(offerId: String, displayName: String, size: UInt64) async {
        let categoryIdentifier = await categories.categoryIdentifier(for: Self.actions)
        let content = UNMutableNotificationContent()
        content.title = "Incoming file"
        let formattedSize = ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file)
        content.body = "\(displayName) (\(formattedSize))"
        content.categoryIdentifier = categoryIdentifier
        await presenter.add(
            UNNotificationRequest(identifier: Self.requestIdentifierPrefix + offerId, content: content, trigger: nil)
        )
    }

    func remove(offerId: String) async {
        await presenter.removeDelivered(identifiers: [Self.requestIdentifierPrefix + offerId])
    }

    func handle(_ event: NotificationResponseEvent) {
        guard let response = Self.response(from: event) else { return }
        continuation.yield(response)
    }

    func finish() {
        continuation.finish()
    }

    static func response(from event: NotificationResponseEvent) -> AcceptPromptResponse? {
        guard event.requestIdentifier.hasPrefix(requestIdentifierPrefix),
              let marker = event.actionIdentifier.range(of: ".action-", options: .backwards),
              let index = Int(event.actionIdentifier[marker.upperBound...]) else { return nil }
        let offerId = String(event.requestIdentifier.dropFirst(requestIdentifierPrefix.count))
        switch index {
        case acceptIndex: return AcceptPromptResponse(offerId: offerId, decision: .accept)
        case declineIndex: return AcceptPromptResponse(offerId: offerId, decision: .decline)
        default: return nil
        }
    }
}
