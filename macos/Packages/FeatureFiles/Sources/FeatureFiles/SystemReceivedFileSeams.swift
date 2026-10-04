import AppKit
import Foundation
@preconcurrency import UserNotifications

/// Production ``ReceivedFilePresenter`` over `UNUserNotificationCenter`. It does not take over the
/// center's delegate: the app's delegate forwards responses to ``handle(_:)``, which claims only
/// this presenter's category.
public final class UNReceivedFilePresenter: ReceivedFilePresenter, @unchecked Sendable {
    public static let categoryIdentifier = "tandem.file.received"
    private static let destinationKey = "destination"

    public let activations: AsyncStream<URL>
    private let continuation: AsyncStream<URL>.Continuation
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        (activations, continuation) = AsyncStream.makeStream()
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryIdentifier, actions: [], intentIdentifiers: [])
        ])
    }

    public func present(displayName: String, destination: URL) async {
        let content = UNMutableNotificationContent()
        content.title = displayName
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [Self.destinationKey: destination.path]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    /// Routes a tap on a received-file notification to ``activations``; returns false for other categories.
    @discardableResult
    public func handle(_ response: UNNotificationResponse) -> Bool {
        let content = response.notification.request.content
        guard content.categoryIdentifier == Self.categoryIdentifier else { return false }
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let path = content.userInfo[Self.destinationKey] as? String {
            continuation.yield(URL(fileURLWithPath: path))
        }
        return true
    }
}

/// Production ``FileRevealer`` over `NSWorkspace.activateFileViewerSelecting`.
public struct WorkspaceFileRevealer: FileRevealer {
    public init() {}

    @MainActor
    private func select(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func reveal(_ url: URL) async {
        await select(url)
    }
}
