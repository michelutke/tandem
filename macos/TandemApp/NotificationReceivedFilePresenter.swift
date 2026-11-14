import FeatureFiles
import FeatureNotifications
import Foundation
@preconcurrency import UserNotifications

/// The received-file notification's copy (ui-spec §7.1: "{file} received", "2.8 GB · saved to
/// Downloads/Tandem").
enum ReceivedFileNotificationCopy {
    static func title(displayName: String) -> String {
        "\(displayName) received"
    }

    static func body(size: Int64?, destination: URL, home: String = NSHomeDirectory()) -> String {
        var folder = destination.deletingLastPathComponent().path
        if folder.hasPrefix(home + "/") { folder.removeFirst(home.count + 1) }
        guard let size else { return "Saved to \(folder)" }
        return "\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) · saved to \(folder)"
    }
}

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
    private var destinationOrder: [String] = []
    private static let maxRememberedDestinations = 50

    init(presenter: any NotificationPresenter) {
        self.presenter = presenter
        (activations, continuation) = AsyncStream<URL>.makeStream(bufferingPolicy: .unbounded)
    }

    func present(displayName: String, destination: URL) async {
        let identifier = Self.requestIdentifierPrefix + UUID().uuidString
        lock.withLock {
            destinations[identifier] = destination
            destinationOrder.append(identifier)
            while destinationOrder.count > Self.maxRememberedDestinations {
                destinations.removeValue(forKey: destinationOrder.removeFirst())
            }
        }
        let content = UNMutableNotificationContent()
        content.title = ReceivedFileNotificationCopy.title(displayName: displayName)
        content.body = ReceivedFileNotificationCopy.body(size: Self.fileSize(of: destination), destination: destination)
        await presenter.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    private static func fileSize(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
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
