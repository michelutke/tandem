import Foundation
import TandemProtocol
@preconcurrency import UserNotifications

/// Maps a `NotificationPosted` (notify.proto, E30-01) to a `UNNotificationRequest` (E30-07).
/// Every displayed string is untrusted peer input and passes through
/// ``DisplayStringSanitizer`` (E01-23/E14-22) first; the E01-22 caps ("Notifications: title",
/// "text/body", "MessagingStyle sender names" in `docs/protocol/SPEC.md`'s caps table) are
/// enforced by the sanitizer's own per-`Kind` cap plus this type's ``maxSenders`` truncation.
///
/// `subtitle` is `package_name` itself: notify.proto's app-name lookup for `package_name` is not
/// yet built (no such lookup exists anywhere in this repo yet), so this issue uses the raw
/// (sanitized) package name rather than inventing one; a future issue can look up and substitute
/// a human-readable app name without changing this builder's shape.
public enum NotificationRequestBuilder {
    /// E01-22's "MessagingStyle sender names" cap: at most 25 names presented per notification.
    public static let maxSenders = 25

    /// Builds the request. `request.identifier` is `posted.key`, so presenting a second
    /// `NotificationPosted` with the same `key` replaces rather than stacks the delivered
    /// notification (`UNUserNotificationCenter.add(_:)`'s own identifier-reuse contract).
    ///
    /// `iconAttachment` (E30-06), when non-nil, becomes the request's single attachment: the
    /// source app's icon, resolved by ``IconCache`` from `posted.packageName` +
    /// `posted.appVersionCode` (a cached icon, or the generic placeholder if none is cached).
    ///
    /// `hideContent` (E30-15) presents only the app name as the title, with empty subtitle and
    /// body, so no title, text or sender name is shown.
    public static func build(
        _ posted: Tandem_V1_NotificationPosted,
        iconAttachment: UNNotificationAttachment? = nil,
        hideContent: Bool = false
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        let appName = DisplayStringSanitizer.sanitize(Data(posted.packageName.utf8), kind: .title)
        if hideContent {
            content.title = appName
        } else {
            content.title = DisplayStringSanitizer.sanitize(Data(posted.title.utf8), kind: .title)
            content.subtitle = appName
            content.body = body(for: posted)
        }
        if let iconAttachment {
            content.attachments = [iconAttachment]
        }
        return UNNotificationRequest(identifier: posted.key, content: content, trigger: nil)
    }

    /// A plain post's body is `text`, sanitized as a `body` string. A `MessagingStyle` post
    /// (non-empty `messaging_style_senders`) instead lists one line per message as
    /// `"Sender: text"`: `text` carries one message per line (LINE FEED-separated, preserved by
    /// the `body` sanitizer kind), in the same order as `messaging_style_senders`, so the two are
    /// paired by position. Senders beyond ``maxSenders`` are dropped, which -- since pairing is
    /// positional -- also drops their corresponding trailing lines.
    private static func body(for posted: Tandem_V1_NotificationPosted) -> String {
        let sanitizedText = DisplayStringSanitizer.sanitize(Data(posted.text.utf8), kind: .body)
        guard !posted.messagingStyleSenders.isEmpty else { return sanitizedText }

        let senders = posted.messagingStyleSenders.prefix(maxSenders).map {
            DisplayStringSanitizer.sanitize(Data($0.utf8), kind: .name)
        }
        let lines = sanitizedText.components(separatedBy: "\n")
        return zip(senders, lines)
            .map { sender, line in "\(sender): \(line)" }
            .joined(separator: "\n")
    }
}
