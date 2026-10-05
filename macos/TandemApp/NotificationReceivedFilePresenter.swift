import FeatureFiles
import FeatureNotifications
import Foundation
@preconcurrency import UserNotifications

/// Presents the received-file notification through the shared ``NotificationPresenter`` seam and
/// republishes a tap as the file's URL on ``activations``. One instance per attached session;
/// ``handle(_:)`` is fed from the single presenter-responses reader. The notification carries only
/// the sanitized file name.
final class NotificationReceivedFilePresenter: ReceivedFilePresenter, @unchecked Sendable {
    static let requestIdentifierPrefix = "tandem.received."

    let activations: AsyncStream<URL>

    private let continuation: AsyncStream<URL>.Continuation
    private let presenter: any NotificationPresenter
    private let lock = NSLock()
    private var destinations: [String: URL] = [:]

    init(presenter: any NotificationPresenter) {
        self.presenter = presenter
        (activations, continuation) = AsyncStream<URL>.makeStream(bufferingPolicy: .unbounded)
    }

    func present(displayName: String, destination: URL) async {
        let identifier = Self.requestIdentifierPrefix + UUID().uuidString
        lock.withLock { destinations[identifier] = destination }
        let content = UNMutableNotificationContent()
        content.title = displayName
        content.body = "Received"
        await presenter.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func handle(_ event: NotificationResponseEvent) {
        guard event.requestIdentifier.hasPrefix(Self.requestIdentifierPrefix),
              event.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let destination = lock.withLock({ destinations.removeValue(forKey: event.requestIdentifier) }) else {
            return
        }
        continuation.yield(destination)
    }

    func finish() {
        continuation.finish()
    }
}
