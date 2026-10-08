import AppKit
import FeatureFiles
import FeatureMirror
import SwiftUI
import TandemDesign
import TandemProtocol

/// Renders ``MenuBarViewModel``'s current state as the menu bar popover (E22-01, ui-spec §7.1):
/// a title pair, then per state the phone's battery numeral and dot gauge with the numbered quick
/// actions (connected), the last-seen explanation and "Retry now" (offline), "Pair phone" (not
/// paired), or the blocked explanation with "Pair again" / "Unpair" (trust error). The shell is
/// ``GlassPopover``. Identifiers and accessibility labels of the earlier plain layout are kept so
/// the existing UI tests keep matching.
struct MenuBarContentView: View {
    let viewModel: MenuBarViewModel

    /// `nil` until a `DeviceStatus` has been received (E23-04) -- the numeral then shows a dash
    /// and ``batteryText`` falls back to ``MenuBarViewModel/batteryPlaceholder``.
    let deviceStatusViewModel: DeviceStatusViewModel?

    /// Opens the pairing window (E22-14); a no-op in scenario/preview hosts.
    var onPairPhone: () -> Void = {}

    /// Opens the manual-mode pairing window for a phone without a usable camera (E73-04); a no-op
    /// in scenario/preview hosts.
    var onPairWithoutCamera: () -> Void = {}

    /// "14:02", for the offline explanation.
    var lastSeenText: String?

    /// The latest fail-closed close code, to tell "Key changed." from "Update needed.".
    var closeCode: CloseCode?

    var onRetry: () -> Void = {}
    var onUnpair: () -> Void = {}

    /// The numbered quick actions, shown only while connected.
    var connectedActions: AnyView = AnyView(EmptyView())

    var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            titleBlock
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityIdentifier("menuBarStateLabel")
                .accessibilityLabel(viewModel.label)
            switch viewModel.state {
            case .notPaired:
                notPaired
            case .connected:
                connected
            case .connecting, .reconnecting:
                EmptyView()
            case .disconnected:
                offline
            case .error:
                blocked
            }
        }
    }

    private var peerTitle: String {
        "\(viewModel.displayName ?? "Tandem")."
    }

    @ViewBuilder
    private var titleBlock: some View {
        switch viewModel.state {
        case .notPaired:
            TitleBlock(subject: "Tandem.", state: "No phone yet.")
        case .connected:
            TitleBlock(subject: peerTitle, state: "Connected.")
        case .connecting:
            TitleBlock(subject: peerTitle, state: "Connecting…")
        case .reconnecting:
            TitleBlock(subject: peerTitle, state: "Reconnecting…")
        case .disconnected:
            TitleBlock(subject: peerTitle, state: "Offline.")
        case .error:
            TitleBlock(
                subject: peerTitle,
                state: closeCode == .versionMismatch ? "Update needed." : "Key changed.",
                isAlert: true
            )
        }
    }

    private var notPaired: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            explanation("Scan a code with the Tandem app on your Android phone. Stays on your local network.")
            Hairline()
            VStack(spacing: 0) {
                NumberedActionRow(index: 1, title: "Pair phone", identifier: "pairPhoneMenuItem", action: onPairPhone)
                NumberedActionRow(
                    index: 2, title: "Pair without camera", identifier: "pairWithoutCameraMenuItem",
                    action: onPairWithoutCamera
                )
            }
            .padding(.horizontal, -TandemSpacing.popoverPadding)
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            batteryRow
            Hairline()
            connectedActions
        }
    }

    private var batteryRow: some View {
        let batteryText = deviceStatusViewModel?.batteryText ?? MenuBarViewModel.batteryPlaceholder
        return VStack(alignment: .leading, spacing: TandemSpacing.small) {
            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(deviceStatusViewModel?.batteryPercent.map(String.init) ?? "—")
                        .tandemTextStyle(TandemTypography.displayNumeral(size: 64))
                        .foregroundStyle(TandemColor.ink)
                    Text("% battery")
                        .tandemTextStyle(TandemTypography.meta())
                        .foregroundStyle(TandemColor.ink2)
                }
                Spacer()
                DotProgress(
                    value: Double(deviceStatusViewModel?.batteryPercent ?? 0) / 100,
                    dotCount: 12
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier("batteryLabel")
            .accessibilityLabel(batteryText)
            if let networkText = deviceStatusViewModel?.networkText {
                Text(networkText)
                    .tandemTextStyle(TandemTypography.meta())
                    .foregroundStyle(TandemColor.ink2)
                    .accessibilityIdentifier("networkLabel")
                    .accessibilityLabel(networkText)
            }
            if let signalBars = deviceStatusViewModel?.signalBars,
               let signalAccessibilityValue = deviceStatusViewModel?.signalAccessibilityValue {
                Text("\(signalBars)")
                    .tandemTextStyle(TandemTypography.metaMono())
                    .foregroundStyle(TandemColor.ink2)
                    .accessibilityIdentifier("signalLabel")
                    .accessibilityValue(signalAccessibilityValue)
            }
        }
    }

    private var offline: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            let seen = lastSeenText.map { "Last seen \($0). " } ?? ""
            explanation("\(seen)Tandem reconnects on its own when the phone is back on this network.")
            Hairline()
            NumberedActionRow(index: 1, title: "Retry now", identifier: "retryNowMenuItem", action: onRetry)
                .padding(.horizontal, -TandemSpacing.popoverPadding)
        }
    }

    @ViewBuilder
    private var blocked: some View {
        let name = viewModel.displayName ?? "The phone"
        if closeCode == .versionMismatch {
            explanation(ErrorBannerViewModel.message(for: .versionMismatch, peerName: viewModel.displayName) ?? "")
        } else {
            explanation(
                "\(name) presented a different key. Tandem blocked the connection. "
                    + "Pair again only if you reset the phone app."
            )
            Hairline()
            VStack(spacing: 0) {
                NumberedActionRow(index: 1, title: "Pair again", identifier: "pairAgainMenuItem", action: onPairPhone)
                NumberedActionRow(index: 2, title: "Unpair", identifier: "unpairMenuItem", action: onUnpair)
            }
            .padding(.horizontal, -TandemSpacing.popoverPadding)
        }
    }

    private func explanation(_ text: String) -> some View {
        Text(text)
            .tandemTextStyle(TandemTypography.body(size: 13))
            .foregroundStyle(TandemColor.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The popover footer (ui-spec §7.1): "Open Tandem" on the left, Settings and Quit as round icon
/// buttons on the right.
struct PopoverFooterView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack {
            Button("Open Tandem") {
                openWindow(id: "main")
                NSApp.activate()
            }
            .buttonStyle(.plain)
            .tandemTextStyle(TandemTypography.rowTitle(size: 12))
            .foregroundStyle(TandemColor.ink)
            .accessibilityIdentifier("openTandemMenuItem")
            .accessibilityLabel("Open Tandem")
            Spacer()
            iconButton("gearshape", label: "Settings…", identifier: "settingsMenuItem") { openSettings() }
            iconButton("power", label: "Quit", identifier: "quitMenuItem") { NSApp.terminate(nil) }
        }
    }

    private func iconButton(
        _ systemName: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(TandemColor.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(TandemColor.ink.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }
}

/// The connected popover's numbered actions (ui-spec §7.1: 01 Send file, 02 Push clipboard,
/// 03 Find phone, 04 Mirror screen, 05 Messages), with the status lines the earlier plain
/// ``QuickActionsView`` showed under them.
struct PopoverActionsView: View {
    let viewModel: QuickActionsViewModel
    let findPhoneViewModel: FindPhoneViewModel
    let pushClipboardViewModel: PushClipboardViewModel
    var mirrorRequestViewModel: MirrorRequestViewModel?
    var sendEntryHandler: SendEntryHandler?
    let onOpenMessages: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(1, "Send file", id: "sendFileMenuItem") { viewModel.select(.sendFile) }
            status(sendEntryHandler?.lastResult?.statusText, id: "sendFileStatusLabel")
            row(2, "Push clipboard", id: "pushClipboardMenuItem") { viewModel.select(.pushClipboard) }
            status(pushClipboardViewModel.statusMessage, id: "pushClipboardStatusLabel")
            row(3, findPhoneTitle, id: "findPhoneMenuItem") { viewModel.select(.findPhone) }
            status(findPhoneViewModel.statusText, id: "findPhoneStatusLabel")
            row(4, "Mirror screen", id: "mirrorPhoneMenuItem") { viewModel.select(.mirror) }
            status(mirrorRequestViewModel?.statusText, id: "mirrorStatusLabel")
            row(5, "Messages", id: "messagesMenuItem", action: onOpenMessages)
        }
        .padding(.horizontal, -TandemSpacing.popoverPadding)
    }

    private var findPhoneTitle: String {
        findPhoneViewModel.label == "Stop Ringing" ? "Stop ringing" : "Find phone"
    }

    private func row(_ index: Int, _ title: String, id: String, action: @escaping () -> Void) -> some View {
        NumberedActionRow(index: index, title: title, identifier: id, action: action)
    }

    @ViewBuilder
    private func status(_ text: String?, id: String) -> some View {
        if let text {
            Text(text)
                .tandemTextStyle(TandemTypography.meta())
                .foregroundStyle(TandemColor.ink2)
                .padding(.horizontal, TandemSpacing.popoverPadding)
                .accessibilityIdentifier(id)
        }
    }
}
