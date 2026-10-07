import AppKit
import SwiftUI

/// Shows ``ToastPill`` in a borderless, non-activating, click-through panel at the top right of the
/// screen under the mouse, so it appears even when the app has no window and is not active. It
/// never takes focus. Fades and slides in, fades out; plain fade under Reduce Motion.
@MainActor
public final class ToastPanelController {
    private static let slideOffset: CGFloat = 12
    private static let fadeDuration: TimeInterval = 0.2

    private var panel: NSPanel?
    private var hosting: NSHostingView<ToastPill>?
    private var generation = 0

    public init() {}

    /// Shows `text`, or hides the toast when `nil`.
    public func show(text: String?) {
        guard let text else {
            hide()
            return
        }
        generation += 1
        let panel = self.panel ?? makePanel()
        let hosting = self.hosting ?? NSHostingView(rootView: ToastPill(text))
        hosting.rootView = ToastPill(text)
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel
        let size = hosting.fittingSize
        let target = Self.frame(size: size)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !panel.isVisible {
            let start = reduceMotion ? target : target.offsetBy(dx: 0, dy: Self.slideOffset)
            panel.setFrame(start, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
        NSAccessibility.post(
            element: panel,
            notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        generation += 1
        let current = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.panel?.orderOut(nil)
            }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }

    private static func frame(size: CGSize) -> CGRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        let margin = TandemSpacing.windowPadding
        return CGRect(
            x: area.maxX - size.width - margin,
            y: area.maxY - size.height - TandemSpacing.medium,
            width: size.width,
            height: size.height
        )
    }
}
