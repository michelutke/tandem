import AppKit
import SwiftUI

/// One button of a ``GlassDialog``; the first action is the primary (filled) one.
public struct GlassDialogAction: Sendable {
    public let title: String
    public let kind: PillButtonKind

    public init(_ title: String, kind: PillButtonKind = .secondary) {
        self.title = title
        self.kind = kind
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
                PillButton(action.title, kind: action.kind) { onChoose(index) }
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
