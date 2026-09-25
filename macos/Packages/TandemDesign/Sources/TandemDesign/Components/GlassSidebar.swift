import SwiftUI

/// One numbered section entry in a ``GlassSidebar`` (Messages, Photos, Calls, Transfers, Devices
/// — ui-spec §7.1 main window).
public struct GlassSidebarSection: Identifiable, Sendable {
    public let id: Int
    public let title: String

    public init(id: Int, title: String) {
        self.id = id
        self.title = title
    }
}

/// The main-window sidebar (ui-spec §5.1): device name + connection-state dot, numbered sections.
public struct GlassSidebar: View {
    private let deviceName: String
    private let isConnected: Bool
    private let sections: [GlassSidebarSection]
    private let onSelect: (GlassSidebarSection) -> Void

    public init(
        deviceName: String,
        isConnected: Bool,
        sections: [GlassSidebarSection],
        onSelect: @escaping (GlassSidebarSection) -> Void
    ) {
        self.deviceName = deviceName
        self.isConnected = isConnected
        self.sections = sections
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.medium) {
            HStack(spacing: TandemSpacing.extraSmall) {
                Circle()
                    .fill(isConnected ? TandemColor.signal : TandemColor.lineUnlit)
                    .frame(width: 8, height: 8)
                Text(deviceName)
                    .tandemTextStyle(TandemTypography.rowTitle())
                    .foregroundStyle(TandemColor.ink)
            }
            .padding(.horizontal, TandemSpacing.popoverPadding)

            VStack(spacing: 0) {
                ForEach(sections) { section in
                    NumberedActionRow(index: section.id, title: section.title) {
                        onSelect(section)
                    }
                }
            }
        }
        .padding(.vertical, TandemSpacing.large)
        .glassSurface(cornerRadius: 0)
    }
}

#Preview {
    GlassSidebar(
        deviceName: "Pixel 9",
        isConnected: true,
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
