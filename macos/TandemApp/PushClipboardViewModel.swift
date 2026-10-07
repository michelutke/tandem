import FeatureClipboard
import Observation

/// Wires the menu bar's "Push Clipboard" quick action (E22-02 stub) to
/// ``ClipboardSender/pushCurrentItem()`` (E31-11): sends the CURRENT pasteboard item right now,
/// through the exact same concealed/transient skip (E31-03) and 1 MiB cap (E31-04) as the
/// automatic poller, rather than waiting for a change to be detected.
///
/// Presentation-independent -- no `SwiftUI` import -- unit-tested against a real ``ClipboardSender``
/// built from `FeatureClipboard`'s own `FakePasteboardSource` (E31-02) and the E12-12
/// `FakeTandemSession` (`@testable import FeatureClipboard`/`TandemProtocol`), the same seam
/// ``FindPhoneViewModel`` already uses. ``QuickActionsView`` reads ``statusMessage`` and calls
/// ``select()`` from its "Push Clipboard" button.
@MainActor
@Observable
final class PushClipboardViewModel {
    static let sentMessage = "Sent to phone."
    static let receivedMessage = "Received from phone."

    /// What ``QuickActionsView`` shows after the last push or received clip: a confirmation, or the
    /// exact string for why nothing was sent -- never the item's actual content (invariant 7).
    private(set) var statusMessage: String?

    private let clipboard: ActiveClipboard
    @ObservationIgnored
    private nonisolated(unsafe) var eventsTask: Task<Void, Never>?

    /// - Parameter clipboard: Routes pushes to the attached session's sender; `nil` before any
    ///   session service exists, in which case ``select()`` is a no-op and nothing is received.
    init(clipboard: ActiveClipboard?) {
        let resolved = clipboard ?? ActiveClipboard()
        self.clipboard = resolved
        eventsTask = Task { [weak self] in
            for await event in resolved.events where event == .received {
                self?.statusMessage = Self.receivedMessage
            }
        }
    }

    /// - Parameter sender: The sender to push the current pasteboard item through, or `nil` if no
    ///   peer is paired yet -- ``select()`` is then a no-op.
    convenience init(sender: ClipboardSender?) {
        let clipboard = ActiveClipboard()
        if let sender { clipboard.attach(sender) }
        self.init(clipboard: clipboard)
    }

    deinit {
        eventsTask?.cancel()
    }

    /// Pushes the current pasteboard item once. No-op while no session is attached.
    func select() {
        let clipboard = clipboard
        Task {
            switch await clipboard.pushCurrentItem() {
            case .sent:
                statusMessage = Self.sentMessage
            case .notSentNoText:
                statusMessage = nil
            case .notSentProtectedItem:
                statusMessage = "Not sent: protected item"
            case .notSentTooLarge:
                statusMessage = ClipboardSender.tooLargeHint
            case nil:
                break
            }
        }
    }
}
