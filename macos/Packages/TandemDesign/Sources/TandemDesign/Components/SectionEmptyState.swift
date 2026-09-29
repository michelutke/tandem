import SwiftUI

/// Shared main-window section empty state (ui-spec §7.1): every section (Messages, Photos, Calls,
/// Transfers, Devices) shows one of these two when it has nothing else to show -- the phone is
/// offline, or the underlying feature is turned off on the phone. Real per-section content
/// composes around this; it never duplicates its copy.
public struct SectionEmptyState: View {
    public enum Kind: Equatable {
        case offline(lastSeenText: String)
        case turnedOffOnPhone
    }

    private let kind: Kind
    private let identifier: String

    public init(kind: Kind, identifier: String) {
        self.kind = kind
        self.identifier = identifier
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.small) {
            switch kind {
            case .offline(let lastSeenText):
                TitleBlock(subject: "Offline.", state: "Seen \(lastSeenText)")
                    .accessibilityIdentifier(identifier)
            case .turnedOffOnPhone:
                Text("Turned off on the phone.")
                    .tandemTextStyle(TandemTypography.body())
                    .foregroundStyle(TandemColor.ink2)
                    .accessibilityIdentifier(identifier)
                    .accessibilityLabel("Turned off on the phone.")
            }
        }
        .padding(TandemSpacing.windowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview("Offline") {
    SectionEmptyState(kind: .offline(lastSeenText: "14:02"), identifier: "offlineEmptyState")
}

#Preview("Turned off") {
    SectionEmptyState(kind: .turnedOffOnPhone, identifier: "turnedOffEmptyState")
}
