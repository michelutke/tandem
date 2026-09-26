import AppKit
import SwiftUI

/// Hosts ``PairingView`` in an `NSWindow` configured so the pairing QR and secret are never
/// exposed to macOS screen capture or sharing (`docs/design/ui-spec.md` §9 "Pairing QR window is
/// excluded from screen capture"; E14-11 acceptance: "sets `NSWindow.sharingType = .none`") and
/// offers no copy or save action of its own -- ``PairingView`` never attaches one.
public final class PairingWindowController: NSWindowController {
    public convenience init(viewModel: PairingViewModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pair"
        window.sharingType = .none
        window.contentViewController = NSHostingController(rootView: PairingView(viewModel: viewModel))
        self.init(window: window)
    }
}
