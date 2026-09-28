import SwiftUI
import TandemDevices

/// Tabs of the Settings window (E22-05).
enum SettingsTab: Hashable {
    case general
    case pairedDevices
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

    @State private var selectedTab: SettingsTab = .general
    @State private var launchAtLoginViewModel: LaunchAtLoginViewModel

    init(pairedDevicesViewModel: PairedDevicesViewModel?) {
        self.pairedDevicesViewModel = pairedDevicesViewModel
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
        TabView(selection: $selectedTab) {
            GeneralSettingsView(viewModel: launchAtLoginViewModel)
                .tabItem { Text("General").accessibilityIdentifier("generalTab") }
                .tag(SettingsTab.general)

            PairedDevicesSettingsView(viewModel: pairedDevicesViewModel)
                .tabItem { Text("Paired Devices").accessibilityIdentifier("pairedDevicesTab") }
                .tag(SettingsTab.pairedDevices)
        }
        .frame(width: 420, height: 320)
        .onAppear { launchAtLoginViewModel.refreshStatus() }
    }
}

private struct GeneralSettingsView: View {
    let viewModel: LaunchAtLoginViewModel

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

            Text("Notification preferences coming soon.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("notificationPrefsPlaceholder")
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
