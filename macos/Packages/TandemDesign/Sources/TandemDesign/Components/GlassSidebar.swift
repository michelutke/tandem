import SwiftUI

/// One numbered section entry in a ``GlassSidebar`` (Messages, Photos, Calls, Transfers, Devices
/// — ui-spec §7.1 main window).
public struct GlassSidebarSection: Identifiable, Sendable, Equatable {
    public let id: Int
    public let title: String

    public init(id: Int, title: String) {
        self.id = id
        self.title = title
    }
}

/// The main-window sidebar (ui-spec §5.1, §7.1): device name + connection-state dot, a
/// "Connected."/"Offline · seen HH:MM" state line, and the numbered sections.
public struct GlassSidebar: View {
    private let deviceName: String
    private let isConnected: Bool
    private let stateText: String
    private let sections: [GlassSidebarSection]
    private let selectedID: Int?
    private let onSelect: (GlassSidebarSection) -> Void

    public init(
        deviceName: String,
        isConnected: Bool,
        stateText: String,
        sections: [GlassSidebarSection],
        selectedID: Int? = nil,
        onSelect: @escaping (GlassSidebarSection) -> Void
    ) {
        self.deviceName = deviceName
        self.isConnected = isConnected
        self.stateText = stateText
        self.sections = sections
        self.selectedID = selectedID
        self.onSelect = onSelect
    }

    /// Space above the device name so it clears the traffic lights of a hidden title bar.
    private static let trafficLightClearance: CGFloat = 52

    public var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            HStack(alignment: .top, spacing: TandemSpacing.extraSmall) {
                Circle()
                    .fill(isConnected ? TandemColor.signal : TandemColor.lineUnlit)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(deviceName)
                        .tandemTextStyle(TandemTypography.rowTitle(size: 18))
                        .foregroundStyle(TandemColor.ink)
                    Text(stateText)
                        .tandemTextStyle(TandemTypography.meta())
                        .foregroundStyle(TandemColor.ink2)
                        .accessibilityIdentifier("sidebarStateLabel")
                        .accessibilityLabel(stateText)
                }
            }
            .padding(.horizontal, TandemSpacing.popoverPadding)

            VStack(spacing: 2) {
                ForEach(sections) { section in
                    NumberedActionRow(
                        index: section.id,
                        title: section.title,
                        identifier: "\(section.title.lowercased())Section",
                        isSelected: section.id == selectedID,
                        emphasizesSelection: true,
                        verticalPadding: TandemSpacing.small,
                        horizontalPadding: TandemSpacing.medium
                    ) {
                        onSelect(section)
                    }
                }
            }
            .padding(.horizontal, TandemSpacing.small)

            Spacer(minLength: 0)
        }
        .padding(.top, Self.trafficLightClearance)
        .padding(.bottom, TandemSpacing.large)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(TandemColor.ink.opacity(0.04))
        .glassSurface(cornerRadius: 0)
        .ignoresSafeArea()
    }
}

#Preview {
    GlassSidebar(
        deviceName: "Pixel 9",
        isConnected: true,
        stateText: "Connected.",
        sections: [
            GlassSidebarSection(id: 1, title: "Messages"),
            GlassSidebarSection(id: 2, title: "Photos"),
            GlassSidebarSection(id: 3, title: "Calls"),
            GlassSidebarSection(id: 4, title: "Transfers"),
            GlassSidebarSection(id: 5, title: "Devices")
        ],
        onSelect: { _ in }
    )
    .frame(width: 220, height: 360)
}
