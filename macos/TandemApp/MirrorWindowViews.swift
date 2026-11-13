import FeatureMirror
import SwiftUI
import TandemDesign

/// The glass toolbar under the mirror stream (ui-spec §7.1 Mirror window): Back, Home, Recents, the
/// "Control on" indicator and a filled Stop. Navigation goes through ``MirrorToolbarModel``, i.e.
/// the window's input sender, never around it.
struct MirrorToolbarView: View {
    let model: MirrorToolbarModel

    var body: some View {
        HStack(spacing: TandemSpacing.small) {
            navigationButton("arrow.left", label: "Back", action: .back)
            navigationButton("circle", label: "Home", action: .home)
            navigationButton("square", label: "Recents", action: .recents)
            Rectangle()
                .fill(TandemColor.line)
                .frame(width: 1, height: 20)
            controlIndicator
            PillButton("Stop") { model.stop() }
                .frame(width: 72)
                .accessibilityIdentifier("mirrorStopButton")
        }
        .padding(TandemSpacing.small)
        .glassSurface(cornerRadius: TandemRadius.popoverWindow)
        .fixedSize()
    }

    @ViewBuilder
    private var controlIndicator: some View {
        if model.isControlOn {
            HStack(spacing: TandemSpacing.small) {
                Circle()
                    .fill(TandemColor.signal)
                    .frame(width: 8, height: 8)
                Text("Control on")
                    .tandemTextStyle(TandemTypography.rowTitle(size: 13))
                    .foregroundStyle(TandemColor.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("mirrorControlOnLabel")
        }
    }

    private func navigationButton(_ symbol: String, label: String, action: MirrorGlobalAction) -> some View {
        Button { model.perform(action) } label: {
            Image(systemName: symbol)
                .foregroundStyle(TandemColor.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.isControlOn)
        .accessibilityLabel(label)
        .accessibilityIdentifier("mirror\(label)Button")
    }
}

/// The dark "Waiting." and "Declined." screens (ui-spec §7.1): a phone-shaped dark panel with the
/// title pair and one glass-wrapped action (Cancel or Close, which is also Escape).
struct MirrorStatusView: View {
    let title: String
    let detail: String
    let actionTitle: String
    let onAction: () -> Void

    var body: some View {
        VStack(spacing: TandemSpacing.large) {
            panel
            PillButton(actionTitle, action: onAction)
                .keyboardShortcut(.cancelAction)
                .frame(width: 88)
                .padding(TandemSpacing.extraSmall)
                .glassSurface(cornerRadius: TandemRadius.popoverWindow)
        }
        .padding(TandemSpacing.windowPadding)
        .frame(minWidth: 300, minHeight: 520)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .tandemTextStyle(TandemTypography.titlePairBold(size: 28))
                .foregroundStyle(TandemColor.paper)
                .accessibilityIdentifier("mirrorStatusTitle")
            Text(detail)
                .tandemTextStyle(TandemTypography.titlePairRegular(size: 28))
                .foregroundStyle(TandemColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("mirrorStatusDetail")
        }
        .padding(TandemSpacing.windowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TandemRadius.sheet, style: .continuous).fill(TandemColor.ink))
    }
}
