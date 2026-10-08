import AppKit
import FeatureNotifications
import SwiftUI
import TandemDesign

/// Shows mirrored notifications as glass cards in a borderless, non-activating panel at the top
/// right of the screen under the mouse, so they appear without system notification permission and
/// without taking focus. Click a card to dismiss it; each also dismisses itself after
/// ``lifetime``. At most ``maxVisible`` cards show, newest on top.
@MainActor
final class NotificationBannerPanelController: NotificationBannerPresenting {
    private static let lifetime: Duration = .seconds(8)
    private static let maxVisible = 3
    private static let margin: CGFloat = 12

    private struct Entry {
        let banner: BannerContent
        let expiry: Task<Void, Never>
    }

    private var entries: [Entry] = []
    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?

    func show(_ banner: BannerContent) async {
        remove(identifier: banner.identifier)
        let identifier = banner.identifier
        let expiry = Task { [weak self] in
            try? await Task.sleep(for: Self.lifetime)
            guard !Task.isCancelled else { return }
            self?.remove(identifier: identifier)
        }
        entries.insert(Entry(banner: banner, expiry: expiry), at: 0)
        while entries.count > Self.maxVisible {
            entries.removeLast().expiry.cancel()
        }
        render()
    }

    func remove(identifier: String) {
        guard let index = entries.firstIndex(where: { $0.banner.identifier == identifier }) else { return }
        entries.remove(at: index).expiry.cancel()
        render()
    }

    private func render() {
        guard !entries.isEmpty else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        let content = AnyView(
            VStack(alignment: .trailing, spacing: Self.margin) {
                ForEach(entries.map(\.banner), id: \.identifier) { banner in
                    NotificationBannerCard(
                        appName: banner.subtitle.isEmpty ? banner.title : banner.subtitle,
                        title: banner.subtitle.isEmpty ? "" : banner.title,
                        message: banner.body,
                        onDismiss: { [weak self] in self?.remove(identifier: banner.identifier) }
                    )
                }
            }
        )
        let hosting = self.hosting ?? NSHostingView(rootView: content)
        hosting.rootView = content
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel
        let size = hosting.fittingSize
        panel.setFrame(Self.frame(size: size), display: true)
        panel.orderFrontRegardless()
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
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.appearance = NSAppearance(named: .aqua)
        panel.excludeFromScreenSharing()
        return panel
    }

    private static func frame(size: CGSize) -> CGRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        return CGRect(
            x: area.maxX - size.width - margin,
            y: area.maxY - size.height - margin,
            width: size.width,
            height: size.height
        )
    }
}
