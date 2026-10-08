import AppKit
import FeatureFiles
import SwiftUI
import TandemDesign
import TandemDevices

/// Tabs of the Settings window (ui-spec §7.1, mac-settings.png).
enum SettingsTab: Hashable, CaseIterable {
    case general
    case notifications
    case files
    case privacy

    var title: String {
        switch self {
        case .general: "General"
        case .notifications: "Notifications"
        case .files: "Files"
        case .privacy: "Privacy"
        }
    }

    var identifier: String {
        switch self {
        case .general: "generalTab"
        case .notifications: "notificationsTab"
        case .files: "filesTab"
        case .privacy: "privacyTab"
        }
    }
}

/// The Settings window's shell (ui-spec §7.1): a "Settings." title, the General, Notifications,
/// Files and Privacy tabs, and hairline rows with ink toggles. Paired devices and key rotation
/// live in the main window's Devices section; Privacy shows this Mac's key.
///
/// `selectedTab` and `launchAtLoginViewModel` live above the tab content, not inside any tab's
/// own view, so switching tabs never recreates either -- a toggle flipped on General keeps its
/// value switching away and back (E22-05 acceptance).
struct SettingsView: View {
    /// `nil` when no rotation composition exists (E70-11) -- the Privacy tab shows a placeholder.
    let rotationViewModel: MacRotationSettingsViewModel?

    @State private var selectedTab: SettingsTab = .general
    @State private var launchAtLoginViewModel: LaunchAtLoginViewModel

    init(rotationViewModel: MacRotationSettingsViewModel? = nil) {
        self.rotationViewModel = rotationViewModel
        #if DEBUG
        if UITestScenario.fromLaunchArguments() != nil {
            _launchAtLoginViewModel = State(initialValue: LaunchAtLoginViewModel(
                service: InMemoryLoginItemService(),
                preferenceStore: InMemoryLaunchAtLoginPreferenceStore()
            ))
            return
        }
        #endif
        _launchAtLoginViewModel = State(initialValue: LaunchAtLoginViewModel(
            service: SMAppServiceLoginItemService(),
            preferenceStore: UserDefaultsLaunchAtLoginPreferenceStore()
        ))
    }

    var body: some View {
        GlassWindow {
            VStack(alignment: .leading, spacing: TandemSpacing.large) {
                Text("Settings.")
                    .tandemTextStyle(TandemTypography.titlePairBold(size: 28))
                    .foregroundStyle(TandemColor.ink)
                // A native `TabView`/`.tabItem` pair does not reliably propagate
                // `.accessibilityIdentifier` to the native tab button, so plain `Button`s drive
                // `selectedTab` directly: they always expose an `XCUIElementTypeButton`.
                HStack(spacing: TandemSpacing.large) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        tabButton(tab)
                    }
                }
                tabContent
                Spacer(minLength: 0)
            }
            .frame(width: 420, height: 320, alignment: .topLeading)
        }
        .onAppear { launchAtLoginViewModel.refreshStatus() }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsView(viewModel: launchAtLoginViewModel)
        case .notifications:
            NotificationsSettingsView()
        case .files:
            FilesSettingsView()
        case .privacy:
            PrivacySettingsView(viewModel: rotationViewModel)
        }
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        Button(tab.title) { selectedTab = tab }
            .buttonStyle(.plain)
            .tandemTextStyle(selectedTab == tab ? TandemTypography.rowTitle(size: 13) : TandemTypography.body(size: 13))
            .foregroundStyle(selectedTab == tab ? TandemColor.ink : TandemColor.ink2)
            .accessibilityIdentifier(tab.identifier)
    }
}

/// A toggle row with a bottom hairline (ui-spec §2: no boxes).
private struct SettingsToggleRow: View {
    let title: String
    let isOn: Binding<Bool>
    let identifier: String

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GlassToggle(title, isOn: isOn)
            .accessibilityIdentifier(identifier)
            .padding(.vertical, TandemSpacing.small)
            .overlay(alignment: .bottom) {
                Rectangle().fill(TandemColor.line(increasedContrast: contrast == .increased)).frame(height: 1)
            }
    }
}

private struct GeneralSettingsView: View {
    let viewModel: LaunchAtLoginViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsToggleRow(
                title: "Launch at login",
                isOn: Binding(get: { viewModel.isEnabled }, set: { viewModel.setEnabled($0) }),
                identifier: "launchAtLoginToggle"
            )
            if let hint = viewModel.approvalHintText {
                Text(hint)
                    .tandemTextStyle(TandemTypography.meta())
                    .foregroundStyle(TandemColor.ink2)
                    .padding(.top, TandemSpacing.small)
            }
        }
    }
}

private struct NotificationsSettingsView: View {
    @AppStorage(NotificationsSessionService.hidesContentWhenLockedKey) private var hidesContentWhenLocked = true

    var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            NotificationDeniedHintView(viewModel: NotificationPermissionViewModel.shared)
            SettingsToggleRow(
                title: "Hide notification text while Mac is locked",
                isOn: $hidesContentWhenLocked,
                identifier: "hideNotificationContentWhenLockedToggle"
            )
        }
    }
}

private struct PrivacySettingsView: View {
    let viewModel: MacRotationSettingsViewModel?

    var body: some View {
        if let viewModel {
            MacRotationSettingsView(viewModel: viewModel)
        } else {
            Text("Key rotation unavailable")
                .tandemTextStyle(TandemTypography.body())
                .foregroundStyle(TandemColor.ink2)
                .accessibilityIdentifier("keyRotationUnavailableLabel")
        }
    }
}

/// The menu bar dropdown's "Settings…" item (E22-05): opens the `Settings` scene declared in
/// `TandemMenuBarApp.body` via the `openSettings` environment action, the same action a real
/// Cmd-, keyboard shortcut resolves to -- this button and Cmd-, always open the identical window.
struct SettingsMenuButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") { openSettings() }
            .accessibilityIdentifier("settingsMenuItem")
            .accessibilityLabel("Settings…")
    }
}

private struct FilesSettingsView: View {
    @State private var folder = DownloadFolderStore.standard.current
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            HairlineRow(key: "Save files to", value: folder.path, valueIsMono: true)
                .accessibilityIdentifier("downloadFolderPathLabel")
            HStack(spacing: TandemSpacing.small) {
                PillButton("Choose…", kind: .secondary) { chooseFolder() }
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("chooseDownloadFolderButton")
                PillButton("Reset", kind: .secondary) {
                    DownloadFolderStore.standard.resetToDefault()
                    folder = DownloadFolderStore.standard.current
                }
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("resetDownloadFolderButton")
            }
            if let errorText {
                Text(errorText)
                    .tandemTextStyle(TandemTypography.meta())
                    .foregroundStyle(TandemColor.alert)
                    .accessibilityIdentifier("downloadFolderErrorLabel")
            }
        }
        .onAppear { folder = DownloadFolderStore.standard.current }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DownloadFolderStore.standard.choose(url)
            errorText = nil
        } catch {
            errorText = "Couldn't use that folder."
        }
        folder = DownloadFolderStore.standard.current
    }
}
