import FeatureFiles
import SwiftUI
import TandemDesign

/// The main window's shell (E22-09, ui-spec §7.1): a ``GlassSidebar`` (device name, connection
/// state, the five numbered sections) and a content area. Real per-section content (Messages,
/// Photos, Calls, Transfers, Devices) lands in later issues; this issue provides only the shared
/// offline/turned-off-on-phone empty states every one of them reuses (``SectionEmptyState``).
struct MainWindowView: View {
    let viewModel: MainWindowViewModel

    /// The attached session's photo service (E22-13); `nil` in scenario hosts, which keep the placeholder.
    var photoService: (any PhotoService)?

    var body: some View {
        HStack(spacing: 0) {
            GlassSidebar(
                deviceName: viewModel.deviceName,
                isConnected: !viewModel.isOffline,
                stateText: viewModel.connectionStateText,
                sections: MainWindowViewModel.sections.map { GlassSidebarSection(id: $0.id, title: $0.title) },
                onSelect: { selected in
                    guard let section = MainWindowViewModel.sections.first(where: { $0.id == selected.id }) else {
                        return
                    }
                    viewModel.select(section)
                }
            )
            .frame(width: 220)

            Divider()

            content
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    @ViewBuilder
    private var content: some View {
        if let section = selectedSection, viewModel.isDisabled(section) {
            SectionEmptyState(kind: .turnedOffOnPhone, identifier: "turnedOffEmptyState")
        } else if case .offline(let lastSeen) = viewModel.connectionState {
            SectionEmptyState(
                kind: .offline(lastSeenText: MainWindowViewModel.formattedTime(lastSeen)),
                identifier: "offlineEmptyState"
            )
        } else if let section = selectedSection, section.title == "Photos", let photoService {
            PhotoGridHost(service: photoService)
        } else if let section = selectedSection {
            Text("\(section.title).")
                .accessibilityIdentifier("sectionPlaceholder")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
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
