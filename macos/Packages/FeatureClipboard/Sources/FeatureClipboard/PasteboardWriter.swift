import AppKit
import TandemProtocol

/// E31-13 (UC-13 main flow): reads `ClipboardText` off the CLIPBOARD channel and writes it to the
/// pasteboard as `public.utf8-plain-text` via ``PasteboardSource/setString(_:forType:)``, the
/// counterpart to E31-04/E31-06's send-side `ClipboardSender`.
///
/// Received text over ``maxTextBytes`` is rejected outright, never truncated, and the pasteboard
/// is left unchanged -- matching `ClipboardSender`'s own oversize handling on the send side.
///
/// A `sensitive` clip (e.g. an Android password manager's `EXTRA_IS_SENSITIVE`) is written with
/// the `org.nspasteboard.ConcealedType`/`TransientType` markers alongside the plain-text type, so
/// clipboard managers and this package's own `ClipboardSender`/`ConcealedTypeFilter` skip it on
/// this machine exactly as they would skip a genuinely concealed item.
///
/// `text` is untrusted peer input and is never logged (invariant 7) -- this type only ever passes
/// it straight to ``PasteboardSource/setString(_:forType:)``, never to any log/print call.
///
/// Every applied write's resulting `changeCount` is recorded into the shared ``ClipboardLoopGuard``
/// (E31-14), so `ClipboardSender`'s poller skips this same write when it next re-detects it as a
/// pasteboard change -- preventing the phone-to-Mac-to-phone echo.
public actor PasteboardWriter {
    /// docs/protocol/SPEC.md #clipboard-channel "Size limit" -- restated from `ClipboardSender`.
    public static let maxTextBytes = 1_048_576

    private let source: any PasteboardSource
    private let session: any TandemSession
    private let loopGuard: ClipboardLoopGuard
    private let onApplied: @Sendable () -> Void

    private var readTask: Task<Void, Never>?

    public init(
        source: any PasteboardSource,
        session: any TandemSession,
        loopGuard: ClipboardLoopGuard = ClipboardLoopGuard(),
        onApplied: @escaping @Sendable () -> Void = {}
    ) {
        self.source = source
        self.session = session
        self.loopGuard = loopGuard
        self.onApplied = onApplied
    }

    /// Starts reading the CLIPBOARD channel. Idempotent: replaces any read loop already running.
    public func start() async {
        readTask?.cancel()
        let stream = await session.receive(.clipboard)
        readTask = Task { [weak self] in
            for await frame in stream {
                guard let self else { return }
                guard case .clipboardText(let clipboardText) = frame.payload else { continue }
                await self.handle(clipboardText)
            }
        }
    }

    /// Stops reading. Callers owning this instance's lifetime should call this before discarding it.
    public func stop() {
        readTask?.cancel()
        readTask = nil
    }

    private func handle(_ clipboardText: Tandem_V1_ClipboardText) async {
        guard clipboardText.text.utf8.count <= Self.maxTextBytes else { return }

        source.clearContents()
        source.setString(clipboardText.text, forType: .string)
        if clipboardText.sensitive {
            source.setString("", forType: ConcealedTypeFilter.concealedType)
            source.setString("", forType: ConcealedTypeFilter.transientType)
        }
        await loopGuard.recordAppliedReceive(changeCount: source.changeCount)
        onApplied()
    }
}
