import Foundation

/// E31-14: prevents the Mac-to-phone-to-Mac echo loop -- the Swift counterpart to Android's own
/// `ClipboardLoopGuard` (E31-08). Shared between ``PasteboardWriter`` (E31-13), which records the
/// pasteboard `changeCount` immediately after applying a received clip's write, and
/// ``ClipboardSender`` (E31-04), whose poller-driven `handleChange` consults it before sending a
/// detected change.
///
/// `NSPasteboard.changeCount` only ever increases (``PasteboardSource``'s own doc comment), so a
/// recorded value can match at most one future poll detection -- the one seeing this type's own
/// just-applied write re-detected, never a later, genuinely new local change. That detection is
/// skipped; any other (necessarily higher) `changeCount` clears the recorded value and is treated
/// as a real local change to send, which is what actually clears the guard from a previous receive.
public actor ClipboardLoopGuard {
    private var recordedChangeCount: Int?

    public init() {}

    /// Called by ``PasteboardWriter`` right after applying a received clip's pasteboard write.
    public func recordAppliedReceive(changeCount: Int) {
        recordedChangeCount = changeCount
    }

    /// Called by ``ClipboardSender`` before sending a detected change. Returns `true` -- skip,
    /// don't send -- when `changeCount` is exactly the applied-receive write being re-detected.
    /// Any other value clears the recorded guard (see this type's own doc comment) and returns
    /// `false`.
    public func shouldSkip(changeCount: Int) -> Bool {
        guard changeCount == recordedChangeCount else {
            recordedChangeCount = nil
            return false
        }
        return true
    }
}
