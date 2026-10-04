import SwiftUI
import TandemDesign

/// The Settings window's "Rotate key" section (E70-11, `docs/design/ui-spec.md` §7.1 Devices):
/// lays out ``MacRotationSettingsViewModel`` with `TandemDesign` components. Deliberately minimal
/// and untested -- the view model carries every rule.
public struct MacRotationSettingsView: View {
    @Bindable private var viewModel: MacRotationSettingsViewModel

    public init(viewModel: MacRotationSettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: TandemSpacing.medium) {
                TitleBlock(subject: "This Mac's key", state: viewModel.currentFingerprint, size: 17)
                    .accessibilityIdentifier("rotationCurrentFingerprint")
                statusContent
                if viewModel.pendingText != nil {
                    pendingContent
                }
                Spacer()
            }

            GlassSheet(isPresented: viewModel.state == .confirming) {
                VStack(alignment: .leading, spacing: TandemSpacing.medium) {
                    TitleBlock(subject: "Rotate this Mac's key?", state: "Your phone must confirm the new key.")
                    PillButton("Rotate", kind: .primary) {
                        Task { await viewModel.confirm() }
                    }
                    PillButton("Cancel", kind: .secondary) {
                        viewModel.cancel()
                    }
                }
                .frame(width: 280)
            }
        }
        .task { viewModel.refreshPending() }
    }

    @ViewBuilder private var statusContent: some View {
        switch viewModel.state {
        case .success(let newFingerprint):
            Text("Key rotated. New key: \(newFingerprint)")
                .tandemTextStyle(TandemTypography.meta())
                .foregroundStyle(TandemColor.ink)
                .accessibilityIdentifier("rotationNewFingerprint")
            PillButton("Done", kind: .secondary) { viewModel.dismissResult() }
        case .failed(let reason):
            Text("Rotation failed: \(reason)")
                .tandemTextStyle(TandemTypography.meta())
                .foregroundStyle(TandemColor.ink2)
            PillButton("Dismiss", kind: .secondary) { viewModel.dismissResult() }
        case .inProgress:
            Text("Rotating key…")
                .tandemTextStyle(TandemTypography.meta())
                .foregroundStyle(TandemColor.ink2)
        case .idle, .confirming:
            PillButton("Rotate key", kind: .primary) { viewModel.requestRotation() }
                .fixedSize(horizontal: true, vertical: false)
                .disabled(!viewModel.actionEnabled)
            if let reason = viewModel.disabledReason {
                Text(reason)
                    .tandemTextStyle(TandemTypography.meta())
                    .foregroundStyle(TandemColor.ink2)
            }
        }
    }

    @ViewBuilder private var pendingContent: some View {
        if let text = viewModel.pendingText {
            Text(text)
                .tandemTextStyle(TandemTypography.meta())
                .foregroundStyle(TandemColor.ink)
            ForEach(viewModel.pendingPhoneNames, id: \.self) { name in
                Text(name)
                    .tandemTextStyle(TandemTypography.meta())
                    .foregroundStyle(TandemColor.ink2)
            }
        }
        if let warning = viewModel.finishWarning {
            Text(warning)
                .tandemTextStyle(TandemTypography.meta())
                .foregroundStyle(TandemColor.ink2)
            PillButton("Finish", kind: .destructive) { Task { await viewModel.finishPending() } }
        }
        PillButton("Cancel rotation", kind: .secondary) { Task { await viewModel.cancelPending() } }
    }
}
