import SwiftUI

/// Shared main-window section empty state (ui-spec §7.1): every section (Messages, Photos, Calls,
/// Transfers, Devices) shows one of these when it has nothing else to show -- the phone is
/// offline, the underlying feature is turned off on the phone, or the phone has not granted
/// access. Real per-section content composes around this; it never duplicates its copy.
public struct SectionEmptyState: View {
    public enum Kind: Equatable {
        case offline(lastSeenText: String)
        case turnedOffOnPhone(section: String, deviceName: String)
        case noAccess(section: String, deviceName: String)

        var subject: String {
            switch self {
            case .offline: "Offline."
            case .turnedOffOnPhone(let section, _), .noAccess(let section, _): "\(section)."
            }
        }

        var stateText: String {
            switch self {
            case .offline(let lastSeenText):
                "Seen \(lastSeenText)"
            case .turnedOffOnPhone(let section, let deviceName):
                "Turned off on the phone. Enable \(section) in Tandem on \(deviceName)."
            case .noAccess(let section, let deviceName):
                "\(deviceName) hasn't shared \(section.lowercased()). Allow access in Tandem on the phone."
            }
        }
    }

    private static let maxTextWidth: CGFloat = 400

    private let kind: Kind
    private let identifier: String

    public init(kind: Kind, identifier: String) {
        self.kind = kind
        self.identifier = identifier
    }

    public var body: some View {
        TitleBlock(subject: kind.subject, state: kind.stateText, size: 26)
            .frame(maxWidth: Self.maxTextWidth, alignment: .leading)
            .accessibilityIdentifier(identifier)
            .padding(TandemSpacing.windowPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview("Offline") {
    SectionEmptyState(kind: .offline(lastSeenText: "14:02"), identifier: "offlineEmptyState")
}

#Preview("Turned off") {
    SectionEmptyState(
        kind: .turnedOffOnPhone(section: "Messages", deviceName: "Pixel 9"), identifier: "turnedOffEmptyState"
    )
}

#Preview("No access") {
    SectionEmptyState(kind: .noAccess(section: "Photos", deviceName: "Pixel 9"), identifier: "noAccessEmptyState")
}
