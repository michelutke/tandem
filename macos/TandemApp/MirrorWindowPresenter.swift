import AppKit
import FeatureMirror
import SwiftUI

/// The mirror NSWindow: one ``MirrorDisplayView`` fed by the decode pipeline, with the glass
/// ``MirrorToolbarView`` under it. The window never takes input unless it is handed a
/// ``MirrorInputSender`` (minted from the `MediaHello` mirror session id, D-77); the toolbar buttons
/// use that same sender.
@MainActor
final class MirrorWindowPresenter: NSObject, MirrorWindowPresenting, NSWindowDelegate {
    private static let toolbarHeight: CGFloat = 68
    private static let contentMinSize = CGSize(width: 320, height: 400)

    private var window: NSWindow?
    private var displayView: MirrorDisplayView?
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
        let toolbarModel = MirrorToolbarModel(inputSender: inputSender, onStop: { [weak self] in
            self?.window?.close()
        })
        let size = Self.initialSize(for: model.streamSize)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height + Self.toolbarHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mirror"
        window.contentView = Self.container(display: view, toolbar: MirrorToolbarView(model: toolbarModel))
        window.contentMinSize = Self.contentMinSize
        window.initialFirstResponder = view
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        displayView = view
        self.model = model
        self.onUserClose = onUserClose
        window.contentView?.layoutSubtreeIfNeeded()
        model.windowResized(view.bounds.size)
        return view
    }

    func dismiss() {
        guard let window else { return }
        window.delegate = nil
        self.window = nil
        displayView = nil
        model = nil
        onUserClose = nil
        window.close()
    }

    func windowDidResize(_ notification: Notification) {
        guard let size = displayView?.bounds.size else { return }
        model?.windowResized(size)
    }

    func windowWillClose(_ notification: Notification) {
        let onUserClose = onUserClose
        window?.delegate = nil
        window = nil
        displayView = nil
        model = nil
        self.onUserClose = nil
        onUserClose?()
    }

    private static func container(display: MirrorDisplayView, toolbar: MirrorToolbarView) -> NSView {
        let container = NSView()
        let bar = NSHostingView(rootView: toolbar)
        for subview in [display, bar] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            display.topAnchor.constraint(equalTo: container.topAnchor),
            display.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            display.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            display.bottomAnchor.constraint(equalTo: bar.topAnchor),
            bar.heightAnchor.constraint(equalToConstant: toolbarHeight),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private static func initialSize(for stream: CGSize) -> CGSize {
        guard stream.width > 0, stream.height > 0 else { return CGSize(width: 360, height: 640) }
        let scale = min(1, 800 / stream.height, 1000 / stream.width)
        return CGSize(width: stream.width * scale, height: stream.height * scale)
    }
}
