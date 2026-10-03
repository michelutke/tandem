import FeatureNotifications
import Foundation
@preconcurrency import UserNotifications

/// Test fixture (E30-07): records every ``NotificationPresenter`` call instead of touching
/// `UNUserNotificationCenter`, so tests never trigger a real notification-authorization prompt.
actor RecordingNotificationPresenter: @preconcurrency NotificationPresenter {
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifierBatches: [[String]] = []
    private(set) var categories: Set<UNNotificationCategory> = []

    nonisolated let responses: AsyncStream<NotificationResponseEvent>
    private let responsesContinuation: AsyncStream<NotificationResponseEvent>.Continuation

    init() {
        let (stream, continuation) = AsyncStream<NotificationResponseEvent>.makeStream(
            bufferingPolicy: .unbounded
        )
        responses = stream
        responsesContinuation = continuation
    }

    func add(_ request: UNNotificationRequest) async {
        addedRequests.append(request)
    }

    func removeDelivered(identifiers: [String]) async {
        removedIdentifierBatches.append(identifiers)
    }

    func setCategories(_ categories: Set<UNNotificationCategory>) async {
        self.categories = categories
    }

    /// Lets a test simulate a `UNNotificationResponse` arriving on ``responses``.
    func inject(_ event: NotificationResponseEvent) {
        responsesContinuation.yield(event)
    }

    /// Identifiers of every ``add(_:)``-ed request, in call order. Isolated accessor so tests
    /// never move a non-`Sendable` `UNNotificationRequest` across the actor boundary themselves.
    var addedIdentifiers: [String] {
        addedRequests.map(\.identifier)
    }

    /// Title, subtitle and body of every ``add(_:)``-ed request, in call order (E30-15).
    var addedContents: [AddedContent] {
        addedRequests.map {
            AddedContent(title: $0.content.title, subtitle: $0.content.subtitle, body: $0.content.body)
        }
    }

    struct AddedContent: Sendable, Equatable {
        let title: String
        let subtitle: String
        let body: String
    }

    /// Bodies of every ``add(_:)``-ed request, in call order (E30-08).
    var addedBodies: [String] {
        addedRequests.map(\.content.body)
    }

    /// Attachment counts of every ``add(_:)``-ed request, in call order (E30-06). Isolated
    /// accessor for the same reason as ``addedIdentifiers``.
    var addedAttachmentCounts: [Int] {
        addedRequests.map { $0.content.attachments.count }
    }
}
