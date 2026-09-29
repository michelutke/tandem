import CryptoKit
import Foundation
@preconcurrency import UserNotifications

/// One phone-side notification action, described independently of `NotificationPosted`'s wire
/// format (no `actions` field exists there yet) so ``CategoryRegistry`` can be built and tested
/// on its own (E30-17). `title` is the action's button label; `isRemoteInput` marks an action the
/// source notification declared as RemoteInput-capable, which registers as a
/// `UNTextInputNotificationAction` rather than a plain `UNNotificationAction`.
public struct NotificationActionSpec: Sendable, Equatable {
    public let title: String
    public let isRemoteInput: Bool

    public init(title: String, isRemoteInput: Bool) {
        self.title = title
        self.isRemoteInput = isRemoteInput
    }
}

/// Registers `UNNotificationCategory` sets with a ``NotificationPresenter`` for phone action sets
/// (E30-17): one `UNNotificationAction` per action in order, a `UNTextInputNotificationAction` for
/// a RemoteInput-capable one, and `.customDismissAction` on every category -- including the
/// dismiss-only category used for a post with no actions at all -- so a Mac-side dismissal
/// reaches ``NotificationPresenter/responses`` (E30-18).
///
/// Category identifiers are derived deterministically from the ordered action set (a SHA-256 of
/// each action's title and RemoteInput flag, in order), so two posts with an identical action set
/// resolve to the same identifier and this registry registers the category with `presenter` only
/// once rather than on every post.
public actor CategoryRegistry {
    /// Category identifier used for a post with no actions at all.
    public static let dismissOnlyCategoryIdentifier = "tandem.category.dismiss-only"

    private let presenter: any NotificationPresenter
    private var actionsByIdentifier: [String: [NotificationActionSpec]] = [:]

    public init(presenter: any NotificationPresenter) {
        self.presenter = presenter
    }

    /// Resolves the category identifier for `actions`, registering a new category with
    /// `presenter` the first time this exact ordered action set is seen. An empty `actions`
    /// resolves to ``dismissOnlyCategoryIdentifier``.
    public func categoryIdentifier(for actions: [NotificationActionSpec]) async -> String {
        let identifier = actions.isEmpty ? Self.dismissOnlyCategoryIdentifier : Self.identifier(for: actions)
        guard actionsByIdentifier[identifier] == nil else { return identifier }

        actionsByIdentifier[identifier] = actions
        let snapshot = actionsByIdentifier
        await presenter.setCategories(Self.makeCategories(from: snapshot))
        return identifier
    }

    private static func makeCategories(
        from actionsByIdentifier: [String: [NotificationActionSpec]]
    ) -> Set<UNNotificationCategory> {
        Set(actionsByIdentifier.map { identifier, actions in makeCategory(identifier: identifier, actions: actions) })
    }

    private static func makeCategory(identifier: String, actions: [NotificationActionSpec]) -> UNNotificationCategory {
        let unActions = actions.enumerated().map { index, spec -> UNNotificationAction in
            let actionIdentifier = "\(identifier).action-\(index)"
            if spec.isRemoteInput {
                return UNTextInputNotificationAction(identifier: actionIdentifier, title: spec.title, options: [])
            }
            return UNNotificationAction(identifier: actionIdentifier, title: spec.title, options: [])
        }
        return UNNotificationCategory(
            identifier: identifier,
            actions: unActions,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
    }

    private static func identifier(for actions: [NotificationActionSpec]) -> String {
        var hasher = SHA256()
        for action in actions {
            hasher.update(data: Data(action.title.utf8))
            hasher.update(data: [0])
            hasher.update(data: [action.isRemoteInput ? 1 : 0])
            hasher.update(data: [0xFF])
        }
        let digest = hasher.finalize()
        return "tandem.category." + digest.map { String(format: "%02x", $0) }.joined()
    }
}
