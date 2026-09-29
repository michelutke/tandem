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
    /// `nil` once a push sends successfully, or before any push has been attempted; otherwise the
    /// exact string ``QuickActionsView`` shows for why nothing was sent -- never the item's actual
    /// content (invariant 7).
    private(set) var statusMessage: String?

    private let sender: ClipboardSender?

    /// - Parameter sender: The sender to push the current pasteboard item through, or `nil` if no
    ///   peer is paired yet -- ``select()`` is then a no-op.
    init(sender: ClipboardSender?) {
        self.sender = sender
    }

    /// Pushes the current pasteboard item once. No-op with no ``sender``.
    func select() {
        guard let sender else { return }
        Task {
            switch await sender.pushCurrentItem() {
            case .sent, .notSentNoText:
                statusMessage = nil
            case .notSentProtectedItem:
                statusMessage = "Not sent: protected item"
            case .notSentTooLarge:
                statusMessage = ClipboardSender.tooLargeHint
            }
        }
    }
}
