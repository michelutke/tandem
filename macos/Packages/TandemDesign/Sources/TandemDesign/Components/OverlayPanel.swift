import AppKit

extension NSPanel {
    /// Keeps this panel out of screen sharing, screenshots by other apps and recordings, so overlay
    /// text such as a mirrored notification body never leaks into a shared screen.
    @MainActor
    public func excludeFromScreenSharing() {
        sharingType = .none
    }
}
