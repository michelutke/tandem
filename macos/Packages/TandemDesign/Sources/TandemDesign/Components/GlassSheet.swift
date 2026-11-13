import SwiftUI

/// A modal confirmation on a 20% scrim (ui-spec §5.1), e.g. "Revoke Pixel 9?". The content itself
/// sits on a glass surface (``glassSurface(cornerRadius:)``). Exposed to accessibility as a modal.
public struct GlassSheet<Content: View>: View {
    private let isPresented: Bool
    private let content: Content

    public init(isPresented: Bool, @ViewBuilder content: () -> Content) {
        self.isPresented = isPresented
        self.content = content()
    }

    public var body: some View {
        if isPresented {
            ZStack {
                TandemColor.ink.opacity(0.2)
                    .ignoresSafeArea()
                content
                    .padding(TandemSpacing.windowPadding)
                    .glassSurface(cornerRadius: TandemRadius.sheet)
            }
            .accessibilityAddTraits(.isModal)
        }
    }
}

/// The standard body of a ``GlassSheet`` confirmation: a bold title, a short explanation, and
/// Cancel (left, secondary) beside the confirming action (right). Escape always cancels. A
/// destructive confirm is never the Return default: Return cancels too, so only a click revokes.
public struct GlassConfirmBody: View {
    private let title: String
    private let message: String
    private let confirmTitle: String
    private let confirmKind: PillButtonKind
    private let confirmIdentifier: String?
    private let isDestructive: Bool
    private let onConfirm: () -> Void
    private let onCancel: () -> Void

    public init(
        title: String,
        message: String,
        confirmTitle: String,
        confirmKind: PillButtonKind,
        confirmIdentifier: String? = nil,
        isDestructive: Bool? = nil,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.confirmKind = confirmKind
        self.confirmIdentifier = confirmIdentifier
        self.isDestructive = isDestructive ?? (confirmKind == .destructive)
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.small) {
            Text(title)
                .tandemTextStyle(TandemTypography.titlePairBold(size: 20))
                .foregroundStyle(TandemColor.ink)
            Text(message)
                .tandemTextStyle(TandemTypography.body(size: 13))
                .foregroundStyle(TandemColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            buttons
                .padding(.top, TandemSpacing.small)
        }
        .frame(width: 320)
    }

    private var buttons: some View {
        HStack(spacing: TandemSpacing.small) {
            PillButton("Cancel", kind: .secondary, action: onCancel)
                .keyboardShortcut(.cancelAction)
            confirmButton
        }
        .keyboardShortcutButton(.defaultAction) { isDestructive ? onCancel() : onConfirm() }
    }

    @ViewBuilder
    private var confirmButton: some View {
        if let confirmIdentifier {
            PillButton(confirmTitle, kind: confirmKind, action: onConfirm)
                .accessibilityIdentifier(confirmIdentifier)
        } else {
            PillButton(confirmTitle, kind: confirmKind, action: onConfirm)
        }
    }
}

#Preview {
    GlassSheet(isPresented: true) {
        GlassConfirmBody(
            title: "Revoke Pixel 9?",
            message: "Its key is deleted here now and on the phone when it next connects. "
                + "Pairing again needs a new code.",
            confirmTitle: "Revoke",
            confirmKind: .destructive,
            onConfirm: {},
            onCancel: {}
        )
    }
}
