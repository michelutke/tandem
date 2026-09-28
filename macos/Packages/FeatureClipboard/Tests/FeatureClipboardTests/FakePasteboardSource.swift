import AppKit
import Synchronization
@testable import FeatureClipboard

/// Test fixture for ``PasteboardSource`` (E31-02): a settable `changeCount` and `typesToReturn`
/// a test can swap out before advancing a shared `ManualTestClock`, standing in for the real
/// `NSPasteboard.general` that only ``NSPasteboardSource`` is permitted to touch. Backed by a
/// `Mutex` (matching `TandemTestSupport.ManualTestClock`'s own convention) since
/// ``PasteboardPoller`` reads it from its own actor while a test mutates it from the test task.
final class FakePasteboardSource: PasteboardSource, Sendable {
    private struct State {
        var changeCount: Int
        var types: [NSPasteboard.PasteboardType]
        var strings: [NSPasteboard.PasteboardType: String] = [:]
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
            $0.strings[type] = string
            $0.changeCount += 1
        }
        return true
    }
}
