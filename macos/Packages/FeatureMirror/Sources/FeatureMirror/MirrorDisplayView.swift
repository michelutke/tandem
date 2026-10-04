import AppKit
import AVFoundation
import CoreMedia

/// Hosts an `AVSampleBufferDisplayLayer` fed by the decode pipeline; the layer is aspect-fit.
public final class MirrorDisplayView: NSView, @preconcurrency SampleBufferSink {
    private let displayLayer = AVSampleBufferDisplayLayer()

    private var keyObservers: [NSObjectProtocol] = []

    /// Receives local view events only (no global monitors, event taps or accessibility APIs).
    public var inputSender: MirrorInputSender? {
        didSet { inputSender?.setWindowKey(window?.isKeyWindow ?? false) }
    }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        displayLayer.videoGravity = .resizeAspect
        layer?.addSublayer(displayLayer)
    }

    public required init?(coder: NSCoder) {
        nil
    }

    public override var acceptsFirstResponder: Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        keyObservers = []
        guard let window else {
            inputSender?.setWindowKey(false)
            return
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncWindowKeyState() }
            })
        }
        inputSender?.setWindowKey(window.isKeyWindow)
    }

    private func syncWindowKeyState() {
        inputSender?.setWindowKey(window?.isKeyWindow ?? false)
    }

    public override func mouseDown(with event: NSEvent) {
        inputSender?.handle(.pressed(point: topLeftPoint(of: event), time: event.timestamp))
    }

    public override func mouseDragged(with event: NSEvent) {
        inputSender?.handle(.dragged(point: topLeftPoint(of: event), time: event.timestamp))
    }

    public override func mouseUp(with event: NSEvent) {
        inputSender?.handle(.released(point: topLeftPoint(of: event), time: event.timestamp))
    }

    public override func scrollWheel(with event: NSEvent) {
        inputSender?.handle(.scrolled(
            point: topLeftPoint(of: event), deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
            time: event.timestamp))
    }

    public override func keyDown(with event: NSEvent) {
        inputSender?.handle(.key(
            characters: event.characters, keyCode: event.keyCode,
            hasCommandModifiers: !event.modifierFlags.isDisjoint(with: [.command, .control])))
    }

    private func topLeftPoint(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }

    public override func layout() {
        super.layout()
        displayLayer.frame = bounds
    }

    public func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(sampleBuffer)
    }
}
