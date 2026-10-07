import AppKit
import FeatureFiles
import SwiftUI
import TandemDevices

/// Tabs of the Settings window (E22-05).
enum SettingsTab: Hashable {
    case general
    case pairedDevices
    case files
    case key
}

/// The Settings window's shell (E22-05, `docs/design/ui-spec.md` "Settings"): a General tab
/// (launch-at-login toggle, notification-prefs placeholder) and a Paired Devices tab hosting the
/// E14-14 list/revoke flow E14-26 already composed with a real `TandemStore.UnpairAction` --
/// this view only ever hosts it, never reimplements it.
///
/// `selectedTab` and `launchAtLoginViewModel` live above the `TabView`, not inside either tab's
/// own content view, so switching tabs never recreates either -- a toggle flipped on General
/// keeps its value switching to Paired Devices and back (E22-05 acceptance).
struct SettingsView: View {
    /// `nil` if no listener ever started (`AppComposition.StartFailure`, or a DEBUG
    /// `-UITestScenario` launch that skips production wiring entirely) -- the Paired Devices tab
    /// then shows a placeholder rather than crashing or silently showing an empty list that looks
    /// like "no paired devices".
    let pairedDevicesViewModel: PairedDevicesViewModel?

    /// `nil` when no rotation composition exists (E70-11) -- the Key tab shows a placeholder.
    let rotationViewModel: MacRotationSettingsViewModel?

    @State private var selectedTab: SettingsTab = .general
    @State private var launchAtLoginViewModel: LaunchAtLoginViewModel

    init(pairedDevicesViewModel: PairedDevicesViewModel?, rotationViewModel: MacRotationSettingsViewModel? = nil) {
        self.pairedDevicesViewModel = pairedDevicesViewModel
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
        VStack(spacing: 0) {
            // A native `TabView`/`.tabItem` pair is the more idiomatic macOS Settings shell, but
            // SwiftUI on macOS does not reliably propagate `.accessibilityIdentifier` set inside a
            // `.tabItem` label closure to the resulting native tab button -- the label view only
            // supplies the tab bar's rendered title/image, not a real node in the accessibility
            // tree UI tests can address by identifier. Plain `Button`s driving `selectedTab`
            // directly are ordinary SwiftUI views with a guaranteed `XCUIElementTypeButton` AX
            // role, so `app.buttons["…Tab"]` reliably finds them (a segmented `Picker`'s AX role
            // on macOS is not guaranteed to be `.buttons` the same way).
            HStack(spacing: 8) {
                tabButton("General", tab: .general, identifier: "generalTab")
                tabButton("Paired Devices", tab: .pairedDevices, identifier: "pairedDevicesTab")
                tabButton("Files", tab: .files, identifier: "filesTab")
                tabButton("Key", tab: .key, identifier: "keyTab")
                Spacer()
            }
            .padding([.horizontal, .top])

            switch selectedTab {
            case .general:
                GeneralSettingsView(viewModel: launchAtLoginViewModel)
            case .pairedDevices:
                PairedDevicesSettingsView(viewModel: pairedDevicesViewModel)
            case .files:
                FilesSettingsView()
            case .key:
                KeySettingsView(viewModel: rotationViewModel)
            }
        }
        .frame(width: 420, height: 320)
        .onAppear { launchAtLoginViewModel.refreshStatus() }
    }

    private func tabButton(_ title: String, tab: SettingsTab, identifier: String) -> some View {
        Button(title) { selectedTab = tab }
            .buttonStyle(.borderless)
            .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary)
            .accessibilityIdentifier(identifier)
    }
}

private struct GeneralSettingsView: View {
    let viewModel: LaunchAtLoginViewModel

    @AppStorage(NotificationsSessionService.hidesContentWhenLockedKey) private var hidesContentWhenLocked = true

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { viewModel.isEnabled },
                set: { viewModel.setEnabled($0) }
            ))
            .accessibilityIdentifier("launchAtLoginToggle")

            if let hint = viewModel.approvalHintText {
                Text(hint)
                    .foregroundStyle(.secondary)
            }

            Toggle("Hide notification content while locked", isOn: $hidesContentWhenLocked)
                .accessibilityIdentifier("hideNotificationContentWhenLockedToggle")
        }
        .padding()
    }
}

private struct PairedDevicesSettingsView: View {
    let viewModel: PairedDevicesViewModel?

    var body: some View {
        if let viewModel {
            PairedDevicesView(viewModel: viewModel)
                .padding()
        } else {
            Text("No paired devices")
                .accessibilityIdentifier("pairedDevicesUnavailableLabel")
                .padding()
        }
    }
}

private struct KeySettingsView: View {
    let viewModel: MacRotationSettingsViewModel?

    var body: some View {
        if let viewModel {
            MacRotationSettingsView(viewModel: viewModel)
                .padding()
        } else {
            Text("Key rotation unavailable")
                .accessibilityIdentifier("keyRotationUnavailableLabel")
                .padding()
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
        Form {
            LabeledContent("Save files to") {
                Text(folder.path)
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .accessibilityIdentifier("downloadFolderPathLabel")
            }
            HStack {
                Button("Choose…") { chooseFolder() }
                    .accessibilityIdentifier("chooseDownloadFolderButton")
                Button("Reset") {
                    DownloadFolderStore.standard.resetToDefault()
                    folder = DownloadFolderStore.standard.current
                }
                .accessibilityIdentifier("resetDownloadFolderButton")
            }
            if let errorText {
                Text(errorText)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("downloadFolderErrorLabel")
            }
        }
        .padding()
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
