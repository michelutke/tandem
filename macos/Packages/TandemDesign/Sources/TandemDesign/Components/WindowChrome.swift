import AppKit
import SwiftUI

/// Makes the hosting window one smooth surface (ui-spec §5.1 `GlassWindow`): transparent title bar
/// with only the traffic lights, content running underneath it, draggable from anywhere.
private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ChromeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .aqua)
        }
    }
}

public extension View {
    /// Applies the transparent-title-bar window chrome to the hosting window.
    func tandemWindowChrome() -> some View {
        background(WindowChromeConfigurator())
    }
}

private struct PopoverChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        PopoverChromeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class PopoverChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.appearance = NSAppearance(named: .aqua)
        }
    }
}

public extension View {
    /// Clears the hosting menu bar window's own backdrop so only the glass surface shows.
    func tandemPopoverChrome() -> some View {
        background(PopoverChromeConfigurator())
    }
}
