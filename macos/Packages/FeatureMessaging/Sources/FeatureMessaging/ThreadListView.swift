import AppKit
import SwiftUI
import TandemDesign

/// The Messages section's thread list (backlog E50-07, ui-spec §7.1): a "Messages." title pair
/// with the unread count, then hairline-separated rows (avatar, name, snippet, unread badge).
public struct ThreadListView: View {
    private let viewModel: ThreadListViewModel

    @Environment(\.colorSchemeContrast) private var contrast

    public init(viewModel: ThreadListViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.large) {
            TitleBlock(subject: "Messages.", state: stateText, size: 26)
            content
        }
        .padding(TandemSpacing.windowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await viewModel.reload() }
    }

    private var stateText: String {
        viewModel.unreadCount > 0 ? "\(viewModel.unreadCount) unread." : "All read."
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            note("Loading messages.", identifier: "threadListLoading")
        case .empty:
            note("No conversations yet.", identifier: "threadListEmpty")
        case .permissionRequired:
            note("Allow SMS access on the phone.", identifier: "threadListPermissionRequired")
        case .loaded:
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.rows) { row in
                        threadRow(row)
                    }
                }
            }
            .accessibilityIdentifier("threadList")
        }
    }

    private func note(_ text: String, identifier: String) -> some View {
        Text(text)
            .tandemTextStyle(TandemTypography.body())
            .foregroundStyle(TandemColor.ink2)
            .accessibilityIdentifier(identifier)
    }

    private func threadRow(_ row: ThreadRow) -> some View {
        HStack(spacing: TandemSpacing.medium) {
            avatar(row)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .tandemTextStyle(TandemTypography.rowTitle())
                    .foregroundStyle(TandemColor.ink)
                    .lineLimit(1)
                Text(row.snippet)
                    .tandemTextStyle(TandemTypography.body())
                    .foregroundStyle(TandemColor.ink2)
                    .lineLimit(1)
            }
            Spacer()
            if let badge = row.unreadBadge {
                Text(badge)
                    .tandemTextStyle(TandemTypography.metaMono())
                    .foregroundStyle(TandemColor.paper)
                    .padding(.horizontal, TandemSpacing.small)
                    .padding(.vertical, TandemSpacing.extraSmall)
                    .background(Capsule().fill(TandemColor.ink))
                    .accessibilityLabel("\(badge) unread")
            }
        }
        .padding(.vertical, TandemSpacing.rowVertical)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TandemColor.line(increasedContrast: contrast == .increased))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("threadRow-\(row.id)")
    }

    @ViewBuilder
    private func avatar(_ row: ThreadRow) -> some View {
        Group {
            if let data = row.avatarThumbnail, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                TandemColor.ink.opacity(0.05)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }
}
