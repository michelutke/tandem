import Synchronization

/// Routes the menu bar's Push Clipboard action to the ``ClipboardSender`` of whichever session is
/// attached, and reports what the user should be told about the clipboard flow. Not connected
/// between sessions.
public final class ActiveClipboard: Sendable {
    public enum Event: Sendable, Equatable {
        /// A clip from the phone was written to the pasteboard.
        case received
    }

    /// Single-consumer; the menu bar view model reads it for its lifetime.
    public let events: AsyncStream<Event>

    private let continuation: AsyncStream<Event>.Continuation
    private let sender = Mutex<ClipboardSender?>(nil)
    private let receivedHandler = Mutex<(@Sendable () -> Void)?>(nil)

    public init() {
        (events, continuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingNewest(8))
    }

    public var isConnected: Bool {
        sender.withLock { $0 } != nil
    }

    public func attach(_ newSender: ClipboardSender) {
        sender.withLock { $0 = newSender }
    }

    public func detach() {
        sender.withLock { $0 = nil }
    }

    /// Pushes the current pasteboard item; `nil` while no session is attached.
    public func pushCurrentItem() async -> ClipboardSender.PushResult? {
        guard let current = sender.withLock({ $0 }) else { return nil }
        return await current.pushCurrentItem()
    }

    /// Called, in addition to ``events``, every time a clip from the phone was written; the toast hook.
    public func setReceivedHandler(_ handler: (@Sendable () -> Void)?) {
        receivedHandler.withLock { $0 = handler }
    }

    func reportReceived() {
        continuation.yield(.received)
        receivedHandler.withLock { $0 }?()
    }
}
