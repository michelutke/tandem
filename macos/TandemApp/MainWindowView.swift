import FeatureFiles
import SwiftUI
import TandemDesign

/// The main window's shell (E22-09, ui-spec §7.1): a ``GlassSidebar`` (device name, connection
/// state, the five numbered sections) and the selected section's content, live from the session
/// (``MainWindowServices``). Messages keeps its cached threads while offline and Devices is always
/// available; Photos, Calls and Transfers show ``SectionEmptyState``'s offline state.
struct MainWindowView: View {
    let viewModel: MainWindowViewModel

    /// `nil` in scenario hosts, which keep the placeholder content.
    var services: MainWindowServices?

    /// Opens the pairing window; a no-op in scenario hosts.
    var onPairPhone: () -> Void = {}

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 0) {
            GlassSidebar(
                deviceName: viewModel.deviceName,
                isConnected: viewModel.isPaired && !viewModel.isOffline,
                stateText: viewModel.connectionStateText,
                sections: MainWindowViewModel.sections.map { GlassSidebarSection(id: $0.id, title: $0.title) },
                selectedID: viewModel.selectedSectionID,
                onSelect: { selected in
                    guard let section = MainWindowViewModel.sections.first(where: { $0.id == selected.id }) else {
                        return
                    }
                    viewModel.select(section)
                }
            )
            .frame(width: 220)

            Rectangle()
                .fill(TandemColor.line(increasedContrast: contrast == .increased))
                .frame(width: 1)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if let services {
                    ErrorBannerView(viewModel: services.errorBanner)
                }
                content
            }
        }
        .frame(minWidth: 980, minHeight: 560)
        .background(TandemColor.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onChange(of: services?.pairedPeer.displayName, initial: true) { syncPeer() }
        .onChange(of: services?.live.deviceStatus?.batteryPercent, initial: true) {
            viewModel.updateBatteryPercent(services?.live.deviceStatus?.batteryPercent)
        }
    }

    private func syncPeer() {
        guard let record = services?.pairedPeer.record else {
            if services != nil { viewModel.updatePeer(name: nil, lastSeen: nil) }
            return
        }
        viewModel.updatePeer(name: record.displayName, lastSeen: record.lastSeen)
    }

    @ViewBuilder
    private var content: some View {
        if let section = selectedSection, viewModel.isDisabled(section) {
            SectionEmptyState(kind: .turnedOffOnPhone, identifier: "turnedOffEmptyState")
        } else if let section = selectedSection, let services {
            liveContent(section, services: services)
        } else if case .offline(let lastSeen) = viewModel.connectionState {
            SectionEmptyState(
                kind: .offline(lastSeenText: MainWindowViewModel.formattedTime(lastSeen)),
                identifier: "offlineEmptyState"
            )
        } else if let section = selectedSection {
            Text("\(section.title).")
                .accessibilityIdentifier("sectionPlaceholder")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
        }
    }

    @ViewBuilder
    private func liveContent(_ section: MainWindowViewModel.Section, services: MainWindowServices) -> some View {
        if section.title == "Devices" {
            DevicesSectionHost(services: services, viewModel: viewModel, onPairPhone: onPairPhone)
        } else if !viewModel.isPaired {
            NotPairedSectionState(onPairPhone: onPairPhone)
        } else if section.title == "Messages" {
            MessagesSectionHost(services: services, viewModel: viewModel)
        } else if case .offline(let lastSeen) = viewModel.connectionState {
            SectionEmptyState(
                kind: .offline(lastSeenText: MainWindowViewModel.formattedTime(lastSeen)),
                identifier: "offlineEmptyState"
            )
        } else {
            connectedContent(section, services: services)
        }
    }

    @ViewBuilder
    private func connectedContent(_ section: MainWindowViewModel.Section, services: MainWindowServices) -> some View {
        switch section.title {
        case "Photos": PhotoGridHost(service: services.photos)
        case "Calls": CallsSectionHost(services: services)
        default: TransfersSectionHost(services: services)
        }
    }

    private var selectedSection: MainWindowViewModel.Section? {
        MainWindowViewModel.sections.first(where: { $0.id == viewModel.selectedSectionID })
    }
}

private struct PhotoGridHost: View {
    @State private var viewModel: PhotoGridViewModel

    init(service: any PhotoService) {
        _viewModel = State(initialValue: PhotoGridViewModel(service: service))
    }

    var body: some View {
        PhotoGridView(viewModel: viewModel)
    }
}
