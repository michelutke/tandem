import SwiftUI
import TandemDesign

/// The main window's Devices section (ui-spec §7.1): per paired phone the name, status, paired
/// date, both key fingerprints, and Rotate key / Revoke, with the revoke and rotate confirmations
/// as glass sheets. Every rule lives in ``PairedDevicesViewModel`` and
/// ``MacRotationSettingsViewModel``.
public struct DevicesSectionView: View {
    @Bindable private var devices: PairedDevicesViewModel
    private let rotation: MacRotationSettingsViewModel?
    private let statusText: (PairedDevicesViewModel.Row) -> String
    private let onPairPhone: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    /// - Parameter statusText: the status line per device ("Connected · last seen now").
    public init(
        devices: PairedDevicesViewModel,
        rotation: MacRotationSettingsViewModel?,
        statusText: @escaping (PairedDevicesViewModel.Row) -> String,
        onPairPhone: @escaping () -> Void
    ) {
        self.devices = devices
        self.rotation = rotation
        self.statusText = statusText
        self.onPairPhone = onPairPhone
    }

    public var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TandemSpacing.large) {
                    header
                    ForEach(devices.rows) { row in
                        deviceBlock(row)
                    }
                }
                .padding(TandemSpacing.windowPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            revokeSheet
            rotateSheet
        }
        .task {
            devices.refresh()
            rotation?.refreshPending()
        }
    }

    /// "1 paired." / "No phone yet." (ui-spec §7.1).
    public static func stateText(pairedCount: Int) -> String {
        pairedCount == 0 ? "No phone yet." : "\(pairedCount) paired."
    }

    private var header: some View {
        HStack(alignment: .top) {
            TitleBlock(subject: "Devices.", state: Self.stateText(pairedCount: devices.rows.count), size: 26)
            Spacer()
            PillButton("Pair phone", kind: .secondary, action: onPairPhone)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("pairPhoneButton")
        }
    }

    private func deviceBlock(_ row: PairedDevicesViewModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HairlineRow(key: "Name", value: row.displayName)
                .overlay(alignment: .top) { hairline }
            HairlineRow(key: "Status", value: statusText(row))
            HairlineRow(key: "Paired", value: row.pairedAtText)
            HairlineRow(key: "Phone key", value: row.fingerprintText, valueIsMono: true)
            if let rotation {
                HairlineRow(
                    key: "This Mac's key",
                    value: FingerprintDisplay.regroup(colonSeparated: rotation.currentFingerprint),
                    valueIsMono: true
                )
            }
            HStack(spacing: TandemSpacing.small) {
                if let rotation {
                    PillButton("Rotate key", kind: .secondary) { rotation.requestRotation() }
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(!rotation.actionEnabled)
                        .accessibilityIdentifier("rotateKeyButton")
                }
                PillButton("Revoke", kind: .destructive) { devices.requestRevoke(row) }
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("revokeButton")
            }
            .padding(.top, TandemSpacing.large)
            if let rotation {
                rotationStatus(rotation)
            }
        }
    }

    @ViewBuilder
    private func rotationStatus(_ rotation: MacRotationSettingsViewModel) -> some View {
        VStack(alignment: .leading, spacing: TandemSpacing.small) {
            switch rotation.state {
            case .success(let newFingerprint):
                note("Key rotated. New key: \(newFingerprint)")
                    .accessibilityIdentifier("rotationNewFingerprint")
                PillButton("Done", kind: .secondary) { rotation.dismissResult() }
                    .fixedSize(horizontal: true, vertical: false)
            case .failed(let reason):
                note("Rotation failed: \(reason)")
                PillButton("Dismiss", kind: .secondary) { rotation.dismissResult() }
                    .fixedSize(horizontal: true, vertical: false)
            case .inProgress:
                note("Rotating key…")
            case .idle, .confirming:
                if let reason = rotation.disabledReason { note(reason) }
            }
            pendingRotation(rotation)
        }
        .padding(.top, TandemSpacing.medium)
    }

    @ViewBuilder
    private func pendingRotation(_ rotation: MacRotationSettingsViewModel) -> some View {
        if let text = rotation.pendingText {
            note(text)
            ForEach(rotation.pendingPhoneNames, id: \.self) { name in
                note(name)
            }
            if let warning = rotation.finishWarning {
                note(warning)
                PillButton("Finish", kind: .destructive) { Task { await rotation.finishPending() } }
                    .fixedSize(horizontal: true, vertical: false)
            }
            PillButton("Cancel rotation", kind: .secondary) { Task { await rotation.cancelPending() } }
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var revokeSheet: some View {
        GlassSheet(isPresented: devices.pendingRevoke != nil) {
            if let pendingRevoke = devices.pendingRevoke {
                VStack(alignment: .leading, spacing: TandemSpacing.medium) {
                    TitleBlock(subject: "Revoke \(pendingRevoke.displayName)?", state: "It will need to pair again.")
                    PillButton("Revoke", kind: .destructive) { devices.confirmRevoke() }
                    PillButton("Cancel", kind: .secondary) { devices.cancelRevoke() }
                }
                .frame(width: 280)
            }
        }
    }

    private var rotateSheet: some View {
        GlassSheet(isPresented: rotation?.state == .confirming) {
            if let rotation {
                VStack(alignment: .leading, spacing: TandemSpacing.medium) {
                    TitleBlock(subject: "Rotate this Mac's key?", state: "Your phone must confirm the new key.")
                    PillButton("Rotate", kind: .primary) { Task { await rotation.confirm() } }
                    PillButton("Cancel", kind: .secondary) { rotation.cancel() }
                }
                .frame(width: 280)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .tandemTextStyle(TandemTypography.meta())
            .foregroundStyle(TandemColor.ink2)
    }

    private var hairline: some View {
        Rectangle().fill(TandemColor.line(increasedContrast: contrast == .increased)).frame(height: 1)
    }
}
