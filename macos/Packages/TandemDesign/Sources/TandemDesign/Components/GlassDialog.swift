import AppKit
import SwiftUI

/// One button of a ``GlassDialog``. The action marked `isSafeDefault` is the dialog's cancel and
/// default role: Escape and Return both choose it, so only a click ever takes the other action.
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

/// App-modal replacement for `NSAlert` on a smooth glass surface (ui-spec §5.1 `GlassSheet`).
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

    /// Ends a running dialog without a choice.
    public static func abort() {
        NSApp.abortModal()
    }
}
