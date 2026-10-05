import AppKit
import FeatureMirror

/// The mirror NSWindow: one ``MirrorDisplayView`` fed by the decode pipeline. The window never
/// takes input unless it is handed a ``MirrorInputSender`` (minted from the `MediaHello` mirror
/// session id, D-77).
@MainActor
final class MirrorWindowPresenter: NSObject, MirrorWindowPresenting, NSWindowDelegate {
    private var window: NSWindow?
    private var model: MirrorWindowModel?
    private var onUserClose: (@MainActor () -> Void)?

    nonisolated override init() {
        super.init()
    }

    func present(
        model: MirrorWindowModel,
        inputSender: MirrorInputSender?,
        onUserClose: @escaping @MainActor () -> Void
    ) -> any SampleBufferSink {
        dismiss()
        let view = MirrorDisplayView(frame: NSRect(origin: .zero, size: model.streamSize))
        view.inputSender = inputSender
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialSize(for: model.streamSize)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mirror"
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        self.model = model
        self.onUserClose = onUserClose
        model.windowResized(view.bounds.size)
        return view
    }

    func dismiss() {
        guard let window else { return }
        window.delegate = nil
        self.window = nil
        model = nil
        onUserClose = nil
        window.close()
    }

    func windowDidResize(_ notification: Notification) {
        guard let size = window?.contentView?.bounds.size else { return }
        model?.windowResized(size)
    }

    func windowWillClose(_ notification: Notification) {
        let onUserClose = onUserClose
        window?.delegate = nil
        window = nil
        model = nil
        self.onUserClose = nil
        onUserClose?()
    }

    private static func initialSize(for stream: CGSize) -> CGSize {
        guard stream.width > 0, stream.height > 0 else { return CGSize(width: 360, height: 640) }
        let scale = min(1, 800 / stream.height, 1000 / stream.width)
        return CGSize(width: stream.width * scale, height: stream.height * scale)
    }
}
