#if DEBUG
// Test double only; compiled out of release builds (E00-30 release scan).
import AppKit
import Synchronization

/// Test fixture for ``PasteboardSource`` (E31-02): a settable `changeCount` and `typesToReturn`
/// a test can swap out before advancing a shared `ManualTestClock`, standing in for the real
/// `NSPasteboard.general` that only ``NSPasteboardSource`` is permitted to touch. Backed by a
/// `Mutex` (matching `TandemTestSupport.ManualTestClock`'s own convention) since
/// ``PasteboardPoller`` reads it from its own actor while a test mutates it from the test task.
///
/// Lives in this main target rather than `FeatureClipboardTests`, mirroring
/// `TandemProtocol.FakeTandemSession`'s own placement and reasoning (E12-12): a sibling package's
/// test target (here, `TandemApp`/`TandemAppTests` for E31-11's ``PushClipboardViewModel``) can
/// only reach this via `@testable import FeatureClipboard`, which needs it in the main target.
final class FakePasteboardSource: PasteboardSource, Sendable {
    private struct State {
        var changeCount: Int
        var types: [NSPasteboard.PasteboardType]
        var strings: [NSPasteboard.PasteboardType: String] = [:]
        var ownedByOtherApp = false
    }

    private let state: Mutex<State>

    init(changeCount: Int = 0, types: [NSPasteboard.PasteboardType] = []) {
        state = Mutex(State(changeCount: changeCount, types: types))
    }

    var changeCount: Int {
        get { state.withLock { $0.changeCount } }
        set { state.withLock { $0.changeCount = newValue } }
    }

    var typesToReturn: [NSPasteboard.PasteboardType] {
        get { state.withLock { $0.types } }
        set { state.withLock { $0.types = newValue } }
    }

    /// Models another app owning the pasteboard: like AppKit, `setString` then fails until
    /// `clearContents()` takes ownership.
    var ownedByOtherApp: Bool {
        get { state.withLock { $0.ownedByOtherApp } }
        set { state.withLock { $0.ownedByOtherApp = newValue } }
    }

    func clearContents() {
        state.withLock {
            $0.strings = [:]
            $0.ownedByOtherApp = false
            $0.changeCount += 1
        }
    }

    func types() -> [NSPasteboard.PasteboardType] {
        state.withLock { $0.types }
    }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        state.withLock { $0.strings[type] }
    }

    /// Mirrors `NSPasteboard.setString(_:forType:)`'s own contract of advancing `changeCount` on
    /// every write (``PasteboardSource``'s doc comment) -- needed so a test driving the real
    /// `PasteboardWriter`/`ClipboardSender` pair (e.g. E31-14's loop-guard tests) sees the same
    /// write-then-poll-detects sequence a real pasteboard would produce.
    @discardableResult
    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        state.withLock {
            guard !$0.ownedByOtherApp else { return false }
            $0.strings[type] = string
            $0.changeCount += 1
            return true
        }
    }
}
#endif
