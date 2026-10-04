import AppKit
import AVFoundation
import CoreMedia

/// Hosts an `AVSampleBufferDisplayLayer` fed by the decode pipeline; the layer is aspect-fit.
public final class MirrorDisplayView: NSView, @preconcurrency SampleBufferSink {
    private let displayLayer = AVSampleBufferDisplayLayer()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        displayLayer.videoGravity = .resizeAspect
        layer?.addSublayer(displayLayer)
    }

    public required init?(coder: NSCoder) {
        nil
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
