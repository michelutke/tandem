import AppKit
import SwiftUI

/// One button of a ``GlassDialog``. The action marked `isSafeDefault` is the dialog's cancel and
/// default role: Escape and Return both choose it, so only a click ever takes the other action.
/// A dialog without one has no default button: Return does nothing and Escape only dismisses it.
public struct GlassDialogAction: Sendable {
    public let title: String
    public let kind: PillButtonKind
    public let isSafeDefault: Bool

    public init(_ title: String, kind: PillButtonKind = .secondary, isSafeDefault: Bool = false) {
        self.title = title
        self.kind = kind
        self.isSafeDefault = isSafeDefault
    }
}

private struct GlassDialogView: View {
    let title: String
    let message: String?
    let actions: [GlassDialogAction]
    let onChoose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            Text(title)
                .tandemTextStyle(TandemTypography.titlePairBold())
                .foregroundStyle(TandemColor.ink)
            if let message {
                Text(message)
                    .tandemTextStyle(TandemTypography.body())
                    .foregroundStyle(TandemColor.ink2)
            }
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                button(for: action, at: index)
            }
        }
        .padding(TandemSpacing.windowPadding)
        .padding(.top, TandemSpacing.large)
        .frame(width: 340)
        .glassSurface(cornerRadius: 0)
        .ignoresSafeArea()
        .tandemWindowChrome()
    }
}

private extension GlassDialogView {
    @ViewBuilder
    func button(for action: GlassDialogAction, at index: Int) -> some View {
        if action.isSafeDefault {
            PillButton(action.title, kind: action.kind) { onChoose(index) }
                .keyboardShortcut(.cancelAction)
                .keyboardShortcutButton(.defaultAction) { onChoose(index) }
        } else {
            PillButton(action.title, kind: action.kind) { onChoose(index) }
        }
    }
}

private final class GlassDialogPanel: NSPanel {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// A non-modal ``GlassDialog`` that can be withdrawn from outside. ``onChoose`` runs at most once,
/// with the chosen action index, or `nil` when Escape dismissed a dialog that has no safe default;
/// ``close()`` withdraws it without calling ``onChoose``.
@MainActor
public final class GlassDialogHandle {
    let panel: NSPanel
    private var onChoose: ((Int?) -> Void)?

    fileprivate init(panel: GlassDialogPanel, onChoose: @escaping (Int?) -> Void) {
        self.panel = panel
        self.onChoose = onChoose
    }

    func choose(_ index: Int?) {
        guard let handler = onChoose else { return }
        onChoose = nil
        panel.orderOut(nil)
        handler(index)
    }

    func show() {
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    public func close() {
        onChoose = nil
        panel.orderOut(nil)
    }
}

/// Replacement for `NSAlert` on a smooth glass surface (ui-spec §5.1 `GlassSheet`).
@MainActor
public enum GlassDialog {
    /// Runs the dialog modally; returns the chosen action index, or `nil` if ``abort()`` ended it.
    public static func runModal(title: String, message: String? = nil, actions: [GlassDialogAction]) -> Int? {
        var chosen: Int?
        let view = GlassDialogView(title: title, message: message, actions: actions) { index in
            chosen = index
            NSApp.stopModal()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.center()
        _ = NSApp.runModal(for: window)
        window.orderOut(nil)
        return chosen
    }

    /// Shows the dialog without blocking the run loop; the caller keeps the handle to withdraw it.
    public static func present(
        title: String,
        message: String? = nil,
        actions: [GlassDialogAction],
        onChoose: @escaping (Int?) -> Void
    ) -> GlassDialogHandle {
        let handle = makeHandle(title: title, message: message, actions: actions, onChoose: onChoose)
        handle.show()
        return handle
    }

    static func makeHandle(
        title: String,
        message: String?,
        actions: [GlassDialogAction],
        onChoose: @escaping (Int?) -> Void
    ) -> GlassDialogHandle {
        weak var handle: GlassDialogHandle?
        let view = GlassDialogView(title: title, message: message, actions: actions) { index in
            handle?.choose(index)
        }
        let panel = GlassDialogPanel(contentViewController: NSHostingController(rootView: view))
        panel.styleMask = [.titled, .fullSizeContentView]
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let created = GlassDialogHandle(panel: panel, onChoose: onChoose)
        handle = created
        panel.onCancel = { [weak created] in created?.choose(nil) }
        return created
    }

    /// Ends a running dialog without a choice.
    public static func abort() {
        NSApp.abortModal()
    }
}
