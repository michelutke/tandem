import AppKit
import CryptoKit
import Foundation
import TandemProtocol

/// E31-04: owns a ``PasteboardPoller`` and sends a qualifying plain-text pasteboard change as
/// `ClipboardText` on the CLIPBOARD channel (docs/protocol/SPEC.md #clipboard-channel), the
/// counterpart to E31-06's Android `ClipboardSender`.
///
/// A detected change is never sent when: its types carry a concealed/transient/auto-generated
/// marker (E31-03's ``ConcealedTypeFilter``, checked *before* any string is read, per that type's
/// own contract); it has no `public.utf8-plain-text` representation at all (images, files, ...);
/// its `changeCount` is exactly a just-applied received clip's write, per the shared
/// ``ClipboardLoopGuard`` (E31-14) -- preventing the phone-to-Mac-to-phone echo; or its UTF-8 byte
/// length exceeds ``maxTextBytes`` -- an over-cap item is rejected outright, never
/// truncated (SPEC.md "Size limit"), and the sending-side hint is recorded in ``hintsShown``
/// instead of a frame being sent.
///
/// The hint is recorded at most once per distinct oversized item, not once per poll tick: dedup is
/// keyed on ``PasteboardSource/changeCount`` at the moment the oversized item was detected, not on
/// the mere fact that ``handleChange(types:)`` ran. In practice ``PasteboardPoller`` itself already
/// calls its `onChange` callback at most once per `changeCount` transition (two ticks that see the
/// same, unchanged `changeCount` produce no callback at all -- see `PasteboardPollerTests`), so this
/// is a second, independent guard against showing the same item's hint twice; `changeCount` is a
/// sufficient key either way, since any new copy -- including a re-copy of identical content --
/// always advances it, so the *next* oversized item, distinct or not, is warned about again once
/// its own `changeCount` differs from the last one warned about.
public actor ClipboardSender {
    /// The outcome of ``pushCurrentItem()`` (E31-11): what an explicit "Push Clipboard" quick
    /// action should show for the current pasteboard item.
    public enum PushResult: Sendable, Equatable {
        /// Sent as `ClipboardText`.
        case sent
        /// Skipped: the item's types carry a concealed/transient/auto-generated marker
        /// (``ConcealedTypeFilter``). The menu must show only "Not sent: protected item" -- never
        /// the item's actual content (invariant 7).
        case notSentProtectedItem
        /// Skipped: the item's UTF-8 text exceeds ``maxTextBytes``. The menu shows
        /// ``tooLargeHint``.
        case notSentTooLarge
        /// Skipped: the current pasteboard item has no `public.utf8-plain-text` representation at
        /// all (an image, a file, ...). Nothing to show -- there is no text to have rejected.
        case notSentNoText
    }

    /// docs/protocol/SPEC.md #clipboard-channel "Size limit", restated from #10
    /// (`#timeouts-connection-limits-and-resource-caps`, E01-22) "Feature caps": `text` MUST be at
    /// most 1,048,576 bytes (1 MiB, 2^20) of UTF-8.
    public static let maxTextBytes = 1_048_576

    /// UC-12 alternate: the Mac-side hint shown when a change is rejected for being over
    /// ``maxTextBytes``.
    public static let tooLargeHint = "Clipboard too large to send, use file transfer"

    private static let originTag = "macos"

    private let source: any PasteboardSource
    private let clock: any Clock<Duration>
    private let session: any TandemSession
    private let loopGuard: ClipboardLoopGuard

    // Built lazily on the first ``start()`` -- not in `init` -- since its `onChange` closure
    // captures `self`, and (matching `HeartbeatController`/`ChannelMultiplexer`'s own convention)
    // an actor cannot form a self-capturing closure inside its own initializer. Kept across a
    // later `stop()`/`start()` pair so ``PasteboardPoller``'s own `lastSeenChangeCount` persists,
    // exactly as if this type held a single long-lived poller from the start.
    private var poller: PasteboardPoller?

    private var lastWarnedChangeCount: Int?

    /// Every "too large" hint shown, in order -- see this type's own doc comment for the dedup
    /// this records.
    public private(set) var hintsShown: [String] = []

    public init(
        source: any PasteboardSource,
        clock: any Clock<Duration>,
        session: any TandemSession,
        loopGuard: ClipboardLoopGuard = ClipboardLoopGuard()
    ) {
        self.source = source
        self.clock = clock
        self.session = session
        self.loopGuard = loopGuard
    }

    /// Starts polling. See ``PasteboardPoller/start()``.
    public func start() async {
        let poller = poller ?? PasteboardPoller(source: source, clock: clock) { [weak self] types in
            await self?.handleChange(types: types)
        }
        self.poller = poller
        await poller.start()
    }

    /// Stops polling. See ``PasteboardPoller/stop()``.
    public func stop() async {
        await poller?.stop()
    }

    private func handleChange(types: [NSPasteboard.PasteboardType]) async {
        guard !ConcealedTypeFilter.shouldSkip(types: types) else { return }
        guard types.contains(.string), let text = source.string(forType: .string) else { return }

        guard await !loopGuard.shouldSkip(changeCount: source.changeCount) else { return }

        await sendIfWithinLimit(text: text)
    }

    /// Sends the CURRENT pasteboard item right now (E31-11), for an explicit "Push Clipboard"
    /// quick action -- independent of ``PasteboardPoller``'s own changeCount-based detection, so
    /// it also sends an item the poller already saw and skipped past (nothing changed since), or
    /// one the poller hasn't polled for yet. Applies the exact same concealed/transient skip
    /// (``ConcealedTypeFilter``) and ``maxTextBytes`` cap as ``handleChange(types:)``.
    ///
    /// Deliberately does *not* consult ``loopGuard``: that guard exists to stop an automatically
    /// *detected* change from echoing a just-received clip back to the phone, but this is the
    /// user's own explicit request to send "whatever is on the pasteboard right now" -- exactly
    /// the "send it again" case this issue exists for (e.g. the phone cleared its clip after
    /// receiving it), so it must not be silently swallowed by the same bookkeeping that guards the
    /// automatic path.
    public func pushCurrentItem() async -> PushResult {
        let types = source.types()
        guard !ConcealedTypeFilter.shouldSkip(types: types) else { return .notSentProtectedItem }
        guard types.contains(.string), let text = source.string(forType: .string) else { return .notSentNoText }
        return await sendIfWithinLimit(text: text) ? .sent : .notSentTooLarge
    }

    @discardableResult
    private func sendIfWithinLimit(text: String) async -> Bool {
        let utf8Bytes = Array(text.utf8)
        guard utf8Bytes.count <= Self.maxTextBytes else {
            warnIfNeeded()
            return false
        }

        var message = Tandem_V1_ClipboardText()
        message.originTag = Self.originTag
        message.contentHash = Data(SHA256.hash(data: Data(utf8Bytes)))
        message.text = text
        try? await session.send(.clipboard, payload: .clipboardText(message))
        return true
    }

    private func warnIfNeeded() {
        let currentChangeCount = source.changeCount
        guard currentChangeCount != lastWarnedChangeCount else { return }
        lastWarnedChangeCount = currentChangeCount
        hintsShown.append(Self.tooLargeHint)
    }
}
